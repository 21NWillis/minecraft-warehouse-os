package dev.nwillis.lens;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.LevelRenderer;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.inventory.ClickType;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterKeyMappingsEvent;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;
import org.lwjgl.glfw.GLFW;

import java.util.ArrayDeque;
import java.util.Deque;

/**
 * The Claude-Control executor: flies the player along a build order and
 * places its blocks, first person, while the operator watches. This is
 * the actuation half of the perception loop - the operator explicitly
 * invited it ("surely a turtle can be a me").
 *
 * SAFETY DOCTRINE (non-negotiable):
 *   * F8 arms/disarms. Nothing moves while disarmed.
 *   * ANY movement input (WASD/jump/sneak), taking damage, opening a
 *     screen, or dying INSTANTLY disarms. The human always wins.
 *   * Place-only: the executor never breaks a block, never attacks,
 *     never touches containers, never drops items.
 *   * Requires creative flight already active (the supremium chest) -
 *     it will not launch a walking player off a cliff.
 *
 * Mechanics: survival-legal placement - the player must HOLD the item
 * (auto-swapped into the hotbar from inventory), be within reach, and
 * click a face of an adjacent existing block. Unreachable/unsupported
 * placements are skipped and retried after the pass; persistent
 * failures are reported and abandoned.
 */
public final class OrderExecutor {
    private enum State { DISARMED, FLYING, PLACING }

    private static KeyMapping armKey;
    private static State state = State.DISARMED;
    private static BuildOrder order;
    private static Deque<BuildOrder.Placement> queue = new ArrayDeque<>();
    private static Deque<BuildOrder.Placement> deferred = new ArrayDeque<>();
    private static int done, total, passes;
    private static int settleTicks;
    // per-placement micro-state: aim a tick before clicking (rotation and
    // hotbar selection sync to the server on the NEXT tick's packets), then
    // wait out the server round-trip and verify the block really exists
    private static int aimTicks, verifyTicks, attempts;
    private static String lastResult = "";
    private static final java.util.Map<String, Integer> results = new java.util.TreeMap<>();
    private static BlockPos lastTarget;
    // optimistic pipeline: clicks are assumed good and verified 6 ticks
    // later; a revert rolls done back and re-queues the block. Entries:
    // {Placement, deadlineGameTime, support, face, eyeDist, result}
    private static final Deque<Object[]> pendingVerify = new ArrayDeque<>();

    public static void registerKeys(RegisterKeyMappingsEvent event) {
        armKey = new KeyMapping("key.paperclip_lens.control", GLFW.GLFW_KEY_F8,
            "key.categories.paperclip_lens");
        event.register(armKey);
    }

    /** ControlOrders hands parsed orders here. */
    public static void submit(BuildOrder o) {
        order = o;
        queue = new ArrayDeque<>(o.placements);
        deferred = new ArrayDeque<>();
        pendingVerify.clear();
        done = 0;
        total = o.placements.size();
        passes = 0;
        say("build order loaded: '" + o.name + "' (" + total
            + " blocks). Press F8 to surrender the body.");
    }

    private static void say(String msg) {
        LocalPlayer p = Minecraft.getInstance().player;
        if (p != null) p.displayClientMessage(Component.literal("§d[lens]§r " + msg), false);
    }

    private static void hud(String msg) {
        LocalPlayer p = Minecraft.getInstance().player;
        if (p != null) p.displayClientMessage(Component.literal(msg), true);
    }

    private static String lastDisarm = "";

    private static void disarm(String why) {
        if (state != State.DISARMED) {
            state = State.DISARMED;
            lastDisarm = why;
            pendingVerify.clear();
            say("control released (" + why + ") - " + done + "/" + total + " placed");
        }
    }

    public static String lastDisarmReason() { return lastDisarm; }

    private static boolean humanInput(Minecraft mc) {
        return mc.options.keyUp.isDown() || mc.options.keyDown.isDown()
            || mc.options.keyLeft.isDown() || mc.options.keyRight.isDown()
            || mc.options.keyJump.isDown() || mc.options.keyShift.isDown();
    }

    public static void onClientTick(ClientTickEvent.Post event) {
        Minecraft mc = Minecraft.getInstance();
        while (armKey != null && armKey.consumeClick()) {
            if (state == State.DISARMED) {
                if (order == null || (queue.isEmpty() && deferred.isEmpty())) {
                    say("no pending build order");
                } else if (mc.player != null && !mc.player.getAbilities().flying) {
                    say("refusing control: not flying (put the supremium chest on)");
                } else {
                    state = State.FLYING;
                    say("control ACTIVE - any movement key releases it");
                }
            } else {
                disarm("F8");
            }
        }
        if (state == State.DISARMED) return;
        LocalPlayer player = mc.player;
        if (player == null || mc.level == null || mc.screen != null
            || player.isDeadOrDying() || player.hurtTime > 0 || humanInput(mc)) {
            disarm(mc.screen != null ? "screen opened"
                : (player != null && player.hurtTime > 0) ? "took damage" : "human input");
            return;
        }
        if (!player.getAbilities().flying) {
            disarm("flight lost");
            return;
        }

        // resolve matured verifications (optimistic pipeline drain)
        while (!pendingVerify.isEmpty()
            && mc.level.getGameTime() >= (long) pendingVerify.peek()[1]) {
            Object[] v = pendingVerify.poll();
            BuildOrder.Placement p = (BuildOrder.Placement) v[0];
            boolean ok = !mc.level.getBlockState(p.pos()).isAir();
            Telemetry.logPlace(p.pos(), (BlockPos) v[2], (Direction) v[3],
                (Double) v[4], (String) v[5], ok, 1);
            if (!ok) {
                done--;
                results.merge("REVERTED", 1, Integer::sum);
                queue.addFirst(p);
            }
        }

        // next placement (retry deferred after each full pass)
        BuildOrder.Placement next = queue.peek();
        if (next == null) {
            if (!pendingVerify.isEmpty()) return;   // let the pipeline drain
            if (deferred.isEmpty()) {
                say("order '" + order.name + "' COMPLETE: " + done + "/" + total
                    + "  click results: " + results);
                results.clear();
                state = State.DISARMED;
                order = null;
                return;
            }
            passes++;
            if (passes > 6) {
                say("abandoning " + deferred.size()
                    + " unreachable/unsupported placements  click results: " + results);
                results.clear();
                queue.clear();
                deferred.clear();
                return;
            }
            queue = deferred;
            deferred = new ArrayDeque<>();
            next = queue.peek();
        }

        BlockPos target = next.pos();
        if (!target.equals(lastTarget)) {
            lastTarget = target;
            attempts = 0;
            resetPlacement();
        }
        // already satisfied? (previous pass, another builder, us)
        if (!mc.level.getBlockState(target).isAir()) {
            queue.poll();
            done++;
            return;
        }

        // Turtle semantics (operator-decreed after flight #4 placed zero
        // blocks): float DIRECTLY over the cell being placed, one block
        // up plus hitbox clearance, and click straight down. Feet at
        // +1.15 puts the eye 2.8 from the support face - 0.7 inside the
        // reach filter - and the tight 0.9 approach kills position slop
        // (flight #4's side-hover left only 0.13 margin and a 2.5-block
        // tolerance, so the face search never once succeeded).
        // +0.85 not +0.65: flight #5 placed 23/23 clicks but ended by
        // settling 0.15 onto its OWN fresh block - landing kills the MA
        // flight augment. Feet at +1.35 keeps 0.35 clearance over a
        // filled cell; the eye stays 2.97 from the click face.
        Vec3 hover = Vec3.atCenterOf(target).add(0, 0.85, 0);
        Vec3 delta = hover.subtract(player.position());
        double dist = delta.length();
        if (dist > 0.9) {
            state = State.FLYING;
            double speed = Math.min(0.9, 0.25 + dist * 0.05);
            Vec3 step = delta.normalize().scale(speed);
            // altitude floor: flight #3 ended because the autopilot flew
            // the body into the ground and the MA flight augment cut out.
            // Never command a descent below one block over the target base.
            if (player.getY() + step.y < target.getY() + 1.2) {
                step = new Vec3(step.x, Math.max(step.y, 0), step.z);
            }
            player.setDeltaMovement(step);
            // face travel direction; feels intentional, reads as piloting
            player.setYRot((float) (Math.atan2(-step.x, step.z) * 180.0 / Math.PI));
            hud("§d[control]§r flying to " + target.toShortString()
                + "  (" + done + "/" + total + ")");
            settleTicks = 0;
            return;
        }
        // brake and settle before interacting
        player.setDeltaMovement(player.getDeltaMovement().scale(0.4));
        if (settleTicks++ < 2) return;
        state = State.PLACING;

        // vanilla refuses to place a block inside an entity - including us.
        // If our hitbox overlaps the target cell, drift up and out first.
        if (player.getBoundingBox().inflate(0.05).intersects(
                new net.minecraft.world.phys.AABB(target))) {
            player.setDeltaMovement(0, 0.25, 0);
            resetPlacement();
            return;
        }

        // find a solid neighbor face to click; track the nearest candidate
        // even when out of reach so failures are diagnosable from the log
        BlockHitResult hit = null;
        double nearestFace = 99;
        for (Direction d : Direction.values()) {
            BlockPos support = target.relative(d);
            if (!mc.level.getBlockState(support).isAir()
                && !mc.level.getBlockState(support).canBeReplaced()) {
                Vec3 face = Vec3.atCenterOf(support)
                    .add(Vec3.atLowerCornerOf(d.getOpposite().getNormal()).scale(0.5));
                double fd = player.getEyePosition().distanceTo(face);
                nearestFace = Math.min(nearestFace, fd);
                if (fd <= 3.5) {
                    hit = new BlockHitResult(face, d.getOpposite(), support, false);
                    break;
                }
            }
        }
        if (hit == null) {
            // orders are support-verified, so "no reachable face" almost
            // always means WE are badly positioned - re-approach and retry
            if (++attempts < 6) {
                resetPlacement();
                return;
            }
            Telemetry.logPlace(target, null, null, nearestFace,
                nearestFace > 90 ? "NO_SOLID_NEIGHBOR" : "NO_FACE_IN_REACH",
                false, attempts);
            attempts = 0;
            queue.poll();
            deferred.add(next);
            resetPlacement();
            hud("§d[control]§r deferred " + target.toShortString()
                + " (no reachable support after retries)");
            return;
        }

        int held = holdItem(mc, player, next.block());
        if (held == 0) {
            disarm("out of " + next.block() + " (restock and re-arm)");
            return;
        }

        // aim now; the click waits a tick so the server has our rotation
        // and hotbar selection BEFORE the use packet arrives (a swap this
        // tick costs one more tick of settling)
        Vec3 eye = player.getEyePosition();
        Vec3 look = hit.getLocation().subtract(eye);
        player.setYRot((float) (Math.atan2(-look.x, look.z) * 180.0 / Math.PI));
        player.setXRot((float) (-Math.atan2(look.y,
            Math.sqrt(look.x * look.x + look.z * look.z)) * 180.0 / Math.PI));
        if (held == 2 || aimTicks++ < 1) return;

        // click and advance immediately: flights 5+ run 100% acceptance,
        // so the 5-tick server round-trip is pure pipeline stall. The
        // drain loop above rolls back and re-queues the rare revert.
        var result = mc.gameMode.useItemOn(player, InteractionHand.MAIN_HAND, hit);
        lastResult = String.valueOf(result);
        results.merge(lastResult, 1, Integer::sum);
        player.swing(InteractionHand.MAIN_HAND);
        pendingVerify.add(new Object[] { next, mc.level.getGameTime() + 6,
            hit.getBlockPos(), hit.getDirection(),
            player.getEyePosition().distanceTo(hit.getLocation()), lastResult });
        queue.poll();
        done++;   // optimistic; the drain loop takes it back on revert
        attempts = 0;
        resetPlacement();
    }

    private static void resetPlacement() {
        aimTicks = 0;
        verifyTicks = 0;
        settleTicks = 0;
    }

    /** Remaining materials bill for the HUD; null when no order loaded. */
    public static java.util.Map<String, Integer> remainingBill() {
        if (order == null) return null;
        java.util.Map<String, Integer> bill = new java.util.TreeMap<>();
        for (BuildOrder.Placement p : queue) bill.merge(p.block(), 1, Integer::sum);
        for (BuildOrder.Placement p : deferred) bill.merge(p.block(), 1, Integer::sum);
        return bill;
    }

    public static String orderName() {
        return order == null ? "" : order.name;
    }

    public static boolean isArmed() {
        return state != State.DISARMED;
    }

    // remote control (CommandBus) - same conditions as F8, same overrides
    public static String remoteArm() {
        Minecraft mc = Minecraft.getInstance();
        if (order == null || (queue.isEmpty() && deferred.isEmpty())) {
            return "no pending build order";
        }
        if (mc.player == null || !mc.player.getAbilities().flying) {
            return "refused: not flying";
        }
        state = State.FLYING;
        say("control ACTIVE (remote) - any movement key releases it");
        return "armed";
    }

    public static String remoteDisarm() {
        disarm("remote");
        return "disarmed";
    }

    // telemetry getters
    public static String stateName() { return state.name(); }
    public static int doneCount() { return done; }
    public static int totalCount() { return total; }
    public static int queuedCount() { return queue.size(); }
    public static int deferredCount() { return deferred.size(); }
    public static int passCount() { return passes; }
    public static String lastClickResult() { return lastResult; }
    public static java.util.Map<String, Integer> resultsTally() { return results; }

    /**
     * Ensure the required block item is in the selected hotbar slot.
     * Returns 0 = not found, 1 = already in hand, 2 = moved this tick
     * (caller must wait a tick for the server to learn about it).
     */
    private static int holdItem(Minecraft mc, LocalPlayer player, String blockId) {
        Inventory inv = player.getInventory();
        ResourceLocation want = ResourceLocation.parse(blockId);
        // already holding it?
        if (matches(inv.getSelected(), want)) return 1;
        // in the hotbar?
        for (int slot = 0; slot < 9; slot++) {
            if (matches(inv.getItem(slot), want)) {
                inv.selected = slot;
                return 2;
            }
        }
        // in the backpack rows? swap it into the selected hotbar slot
        for (int slot = 9; slot < 36; slot++) {
            if (matches(inv.getItem(slot), want)) {
                mc.gameMode.handleInventoryMouseClick(
                    player.inventoryMenu.containerId,
                    slot < 27 ? slot + 9 : slot - 27,   // container slot mapping
                    inv.selected, ClickType.SWAP, player);
                return matches(inv.getSelected(), want) ? 2 : 0;
            }
        }
        return 0;
    }

    private static boolean matches(ItemStack stack, ResourceLocation want) {
        if (stack.isEmpty() || !(stack.getItem() instanceof BlockItem)) return false;
        return want.equals(BuiltInRegistries.ITEM.getKey(stack.getItem()));
    }

    /** Ghost-render the remaining placements: the blueprint hangs in the air. */
    public static void onRenderLevel(RenderLevelStageEvent event) {
        if (order == null) return;
        if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_PARTICLES) return;
        Minecraft mc = Minecraft.getInstance();
        Vec3 cam = event.getCamera().getPosition();
        PoseStack ps = event.getPoseStack();
        MultiBufferSource.BufferSource buffers = mc.renderBuffers().bufferSource();
        VertexConsumer lines = buffers.getBuffer(RenderType.lines());
        int shown = 0;
        for (BuildOrder.Placement p : queue) {
            if (shown++ > 400) break;   // keep the frame rate honest
            BlockPos b = p.pos();
            if (!b.closerThan(BlockPos.containing(cam), 96)) continue;
            ps.pushPose();
            ps.translate(b.getX() - cam.x, b.getY() - cam.y, b.getZ() - cam.z);
            boolean isNext = p == queue.peek();
            LevelRenderer.renderLineBox(ps, lines, 0.08, 0.08, 0.08, 0.92, 0.92, 0.92,
                isNext ? 0.2f : 0.85f, isNext ? 1.0f : 0.4f, isNext ? 0.4f : 0.95f, 0.9f);
            ps.popPose();
        }
        buffers.endBatch(RenderType.lines());
    }
}
