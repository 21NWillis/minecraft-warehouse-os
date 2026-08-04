package dev.nwillis.lens;

import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.client.event.RenderGuiEvent;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * The pre-flight checklist (operator-requested): while a build order is
 * loaded, a HUD panel shows every remaining material with have/need
 * counts read live from the player's inventory. All lines green =
 * "GO - press F8". No more arming a build and discovering mid-air that
 * the deepslate stayed in a chest.
 */
public final class MaterialsHud {

    public static void onRenderGui(RenderGuiEvent.Post event) {
        Minecraft mc = Minecraft.getInstance();
        LocalPlayer player = mc.player;
        if (player == null || mc.options.hideGui) return;
        Map<String, Integer> bill = OrderExecutor.remainingBill();
        if (bill == null || bill.isEmpty()) return;

        List<String> lines = new ArrayList<>();
        boolean go = true;
        int shown = 0;
        for (Map.Entry<String, Integer> e : bill.entrySet()) {
            int have = countInInventory(player, e.getKey());
            boolean ok = have >= e.getValue();
            if (!ok) go = false;
            if (shown++ < 10) {
                String name = shortName(e.getKey());
                lines.add((ok ? "§a✔ " : "§c✘ ") + name + " §7"
                    + Math.min(have, e.getValue()) + "/" + e.getValue());
            }
        }
        if (shown > 10) lines.add("§7… +" + (shown - 10) + " more");
        String title = "§d⛏ " + OrderExecutor.orderName();
        String status = OrderExecutor.isArmed() ? "§dBUILDING…"
            : go ? "§a§lGO — press F8" : "§c§lmissing materials";

        GuiGraphics g = event.getGuiGraphics();
        int x = 6;
        int y = mc.getWindow().getGuiScaledHeight() / 2 - (lines.size() * 10 + 30) / 2;
        int width = mc.font.width(title);
        for (String l : lines) width = Math.max(width, mc.font.width(l));
        width = Math.max(width, mc.font.width(status)) + 8;
        g.fill(x - 3, y - 4, x + width, y + lines.size() * 10 + 24, 0x90000000);
        g.drawString(mc.font, title, x, y, 0xFFFFFF);
        int ly = y + 12;
        for (String l : lines) {
            g.drawString(mc.font, l, x, ly, 0xFFFFFF);
            ly += 10;
        }
        g.drawString(mc.font, status, x, ly + 2, 0xFFFFFF);
    }

    private static int countInInventory(LocalPlayer player, String blockId) {
        ResourceLocation want = ResourceLocation.parse(blockId);
        int total = 0;
        for (int slot = 0; slot < player.getInventory().getContainerSize(); slot++) {
            ItemStack stack = player.getInventory().getItem(slot);
            if (!stack.isEmpty() && stack.getItem() instanceof BlockItem
                && want.equals(BuiltInRegistries.ITEM.getKey(stack.getItem()))) {
                total += stack.getCount();
            }
        }
        return total;
    }

    private static String shortName(String id) {
        int colon = id.indexOf(':');
        return colon >= 0 ? id.substring(colon + 1) : id;
    }
}
