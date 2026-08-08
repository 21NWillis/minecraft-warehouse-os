package dev.nwillis.lens;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.RegisterClientCommandsEvent;

/**
 * In-game setup commands - no config file editing, no restarts:
 *   /bottomleft   set world-model corner A at your feet
 *   /topright     set world-model corner B at your feet
 *   /datum        set the campus datum at your feet; build orders with
 *                 "fromDatum" coordinates resolve against it
 * Corners can be run in either order and any relative position - the
 * model normalizes per axis. Fly to the spot, type the word, done.
 */
public final class ClientCommands {
    public static void register(RegisterClientCommandsEvent event) {
        CommandDispatcher<CommandSourceStack> d = event.getDispatcher();
        d.register(Commands.literal("bottomleft")
            .executes(ctx -> corner(ctx.getSource(), true)));
        d.register(Commands.literal("topright")
            .executes(ctx -> corner(ctx.getSource(), false)));
        d.register(Commands.literal("datum")
            .executes(ctx -> datum(ctx.getSource())));
        // /fieldsnap [radius] [down] [up] - one-shot site inspection
        // around the player; never touches the campus model or config
        d.register(Commands.literal("fieldsnap")
            .executes(ctx -> fieldsnap(ctx.getSource(), 48, 32, 16))
            .then(Commands.argument("radius", IntegerArgumentType.integer(4, 128))
                .executes(ctx -> fieldsnap(ctx.getSource(),
                    IntegerArgumentType.getInteger(ctx, "radius"), 32, 16))
                .then(Commands.argument("down", IntegerArgumentType.integer(0, 128))
                    .executes(ctx -> fieldsnap(ctx.getSource(),
                        IntegerArgumentType.getInteger(ctx, "radius"),
                        IntegerArgumentType.getInteger(ctx, "down"), 16))
                    .then(Commands.argument("up", IntegerArgumentType.integer(0, 128))
                        .executes(ctx -> fieldsnap(ctx.getSource(),
                            IntegerArgumentType.getInteger(ctx, "radius"),
                            IntegerArgumentType.getInteger(ctx, "down"),
                            IntegerArgumentType.getInteger(ctx, "up")))))));
    }

    private static int fieldsnap(CommandSourceStack src, int r, int down, int up) {
        BlockPos p = BlockPos.containing(src.getPosition());
        String status = FieldSnap.start(p, r, down, up);
        src.sendSuccess(() -> Component.literal(status), false);
        return 1;
    }

    private static int corner(CommandSourceStack src, boolean minCorner) {
        BlockPos p = BlockPos.containing(src.getPosition());
        int[] v = new int[] { p.getX(), p.getY(), p.getZ() };
        if (minCorner) {
            PaperclipLens.CONFIG.baseMin = v;
        } else {
            PaperclipLens.CONFIG.baseMax = v;
        }
        PaperclipLens.CONFIG.save(FMLPaths.CONFIGDIR.get());
        String status = WorldModel.arm();
        String which = minCorner ? "baseMin" : "baseMax";
        src.sendSuccess(() -> Component.literal(
            which + " = [" + p.toShortString() + "] saved; " + status), false);
        return 1;
    }

    private static int datum(CommandSourceStack src) {
        BlockPos p = BlockPos.containing(src.getPosition());
        PaperclipLens.CONFIG.datum = new int[] { p.getX(), p.getY(), p.getZ() };
        PaperclipLens.CONFIG.save(FMLPaths.CONFIGDIR.get());
        src.sendSuccess(() -> Component.literal(
            "datum = [" + p.toShortString()
                + "] saved; fromDatum orders now resolve here"), false);
        return 1;
    }
}
