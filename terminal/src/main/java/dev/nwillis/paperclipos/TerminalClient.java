package dev.nwillis.paperclipos;

import net.minecraft.client.Minecraft;

/** Client-only glue; loaded only when invoked from the client path. */
public final class TerminalClient {
    public static void open(TerminalBlockEntity be) {
        Minecraft.getInstance().setScreen(new TerminalScreen(be));
    }
}
