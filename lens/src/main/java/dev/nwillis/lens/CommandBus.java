package dev.nwillis.lens;

import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.network.chat.Component;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Remote command verbs, dropped into orders/ as {"cmd": "..."} files by
 * the dev side. The operator invited full remote debugging ("set up full
 * control... you are going to debug until this works"), so arm/disarm can
 * be driven remotely - but every human-override disarm in OrderExecutor
 * still applies untouched: any movement key, damage, or screen instantly
 * returns the body. The human always wins.
 *
 * Verbs: arm, disarm, snapshot (F10 equivalent), screenshot [name]
 * (writes screenshots/<name>.png for the dev side to look at), say [msg].
 */
public final class CommandBus {
    public static void run(JsonObject cmd) {
        Minecraft mc = Minecraft.getInstance();
        String verb = cmd.has("cmd") ? cmd.get("cmd").getAsString() : "?";
        String outcome;
        switch (verb) {
            case "arm" -> outcome = OrderExecutor.remoteArm();
            case "disarm" -> outcome = OrderExecutor.remoteDisarm();
            case "snapshot" -> outcome = WorldModel.snapshot();
            case "screenshot" -> {
                String name = cmd.has("name") ? cmd.get("name").getAsString()
                    : ("lens_" + System.currentTimeMillis());
                mc.execute(() -> Screenshot.grab(FMLPaths.GAMEDIR.get().toFile(),
                    name + ".png", mc.getMainRenderTarget(), c -> {}));
                outcome = "screenshot " + name + ".png";
            }
            case "say" -> {
                if (mc.player != null && cmd.has("msg")) {
                    mc.player.displayClientMessage(Component.literal(
                        "§d[claude]§r " + cmd.get("msg").getAsString()), false);
                }
                outcome = "said";
            }
            default -> outcome = "unknown cmd '" + verb + "'";
        }
        if (mc.player != null && !"say".equals(verb)) {
            mc.player.displayClientMessage(Component.literal(
                "§d[lens]§r cmd " + verb + ": " + outcome), false);
        }
        Telemetry.logCmd(verb, outcome);
        PaperclipLens.LOG.info("cmd {}: {}", verb, outcome);
    }
}
