package dev.nwillis.lens;

import com.mojang.brigadier.CommandDispatcher;
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
