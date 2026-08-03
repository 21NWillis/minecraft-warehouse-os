package dev.nwillis.lens;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.renderer.LevelRenderer;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.Nameable;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterKeyMappingsEvent;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;
import org.joml.Matrix4f;
import org.lwjgl.glfw.GLFW;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Outlines every ComputerCraft turtle in range and floats its label over it -
 * so Constructor-1 on layer 30 is a glowing box with a name, not a squinting
 * exercise. Detection is by block-entity registry key (namespace
 * "computercraft", path containing "turtle"): no compile dependency on CC.
 */
public final class TurtleEsp {
    private record Hit(BlockPos pos, String label) {}

    private static KeyMapping toggle;
    private static boolean enabled;
    private static long lastScan = Long.MIN_VALUE;
    private static final List<Hit> hits = new ArrayList<>();

    public static void registerKeys(RegisterKeyMappingsEvent event) {
        toggle = new KeyMapping("key.paperclip_lens.esp", GLFW.GLFW_KEY_F9,
            "key.categories.paperclip_lens");
        event.register(toggle);
        enabled = PaperclipLens.CONFIG.espOnByDefault;
    }

    public static void onClientTick(ClientTickEvent.Post event) {
        Minecraft mc = Minecraft.getInstance();
        while (toggle != null && toggle.consumeClick()) {
            enabled = !enabled;
            if (mc.player != null) {
                mc.player.displayClientMessage(
                    Component.literal("turtle ESP " + (enabled ? "on" : "off")), true);
            }
        }
        if (!enabled || mc.level == null || mc.player == null) return;
        if (mc.level.getGameTime() - lastScan < 20) return;   // rescan 1/s
        lastScan = mc.level.getGameTime();

        hits.clear();
        int radius = Math.max(16, PaperclipLens.CONFIG.espRadius);
        ChunkPos center = mc.player.chunkPosition();
        int chunkRadius = (radius >> 4) + 1;
        for (int cx = -chunkRadius; cx <= chunkRadius; cx++) {
            for (int cz = -chunkRadius; cz <= chunkRadius; cz++) {
                LevelChunk chunk = mc.level.getChunkSource()
                    .getChunk(center.x + cx, center.z + cz, false);
                if (chunk == null) continue;
                for (Map.Entry<BlockPos, BlockEntity> entry : chunk.getBlockEntities().entrySet()) {
                    BlockEntity be = entry.getValue();
                    ResourceLocation key = BuiltInRegistries.BLOCK_ENTITY_TYPE.getKey(be.getType());
                    if (key == null || !key.getNamespace().equals("computercraft")
                        || !key.getPath().contains("turtle")) continue;
                    if (!entry.getKey().closerThan(mc.player.blockPosition(), radius)) continue;
                    String label = be instanceof Nameable n && n.hasCustomName()
                        ? n.getCustomName().getString() : "turtle";
                    hits.add(new Hit(entry.getKey().immutable(), label));
                }
            }
        }
    }

    public static void onRenderLevel(RenderLevelStageEvent event) {
        if (!enabled || hits.isEmpty()) return;
        if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_PARTICLES) return;

        Minecraft mc = Minecraft.getInstance();
        Vec3 cam = event.getCamera().getPosition();
        PoseStack ps = event.getPoseStack();
        MultiBufferSource.BufferSource buffers = mc.renderBuffers().bufferSource();

        VertexConsumer lines = buffers.getBuffer(RenderType.lines());
        for (Hit h : hits) {
            ps.pushPose();
            ps.translate(h.pos().getX() - cam.x, h.pos().getY() - cam.y, h.pos().getZ() - cam.z);
            LevelRenderer.renderLineBox(ps, lines, -0.02, -0.02, -0.02,
                1.02, 1.02, 1.02, 1.0f, 0.35f, 0.9f, 1.0f);
            ps.popPose();
        }
        buffers.endBatch(RenderType.lines());

        Font font = mc.font;
        for (Hit h : hits) {
            ps.pushPose();
            ps.translate(h.pos().getX() + 0.5 - cam.x,
                h.pos().getY() + 1.4 - cam.y,
                h.pos().getZ() + 0.5 - cam.z);
            ps.mulPose(event.getCamera().rotation());
            ps.scale(-0.025f, -0.025f, 0.025f);
            Matrix4f pose = ps.last().pose();
            double dist = Math.sqrt(h.pos().distToCenterSqr(cam.x, cam.y, cam.z));
            String text = h.label() + " (" + (int) dist + "m)";
            font.drawInBatch(text, -font.width(text) / 2f, 0, 0xFFFFFFFF, false,
                pose, buffers, Font.DisplayMode.SEE_THROUGH, 0x40000000, 0xF000F0);
            ps.popPose();
        }
        buffers.endBatch();
    }
}
