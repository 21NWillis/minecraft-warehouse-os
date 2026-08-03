package dev.nwillis.lens;

import net.minecraft.ChatFormatting;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.event.entity.player.ItemTooltipEvent;

import java.text.NumberFormat;
import java.util.Locale;

/** Appends the Paperclip Exchange value (and live warehouse stock) to tooltips. */
public final class TooltipHandler {
    private static final NumberFormat INT = NumberFormat.getIntegerInstance(Locale.US);

    public static void onTooltip(ItemTooltipEvent event) {
        if (!PaperclipLens.CONFIG.emcTooltips || !EmcIndex.ready()) return;
        ItemStack stack = event.getItemStack();
        if (stack.isEmpty()) return;

        String id = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();

        Double emc = EmcIndex.get(id);
        if (emc != null) {
            MutableComponent line = Component.literal("EMC " + fmt(emc))
                .withStyle(ChatFormatting.LIGHT_PURPLE);
            if (stack.getCount() > 1) {
                line.append(Component.literal("  (" + fmt(emc * stack.getCount()) + " total)")
                    .withStyle(ChatFormatting.DARK_GRAY));
            }
            event.getToolTip().add(line);
        }

        Long have = StockIndex.get(id);
        if (have != null) {
            event.getToolTip().add(Component.literal("warehouse: " + INT.format(have))
                .withStyle(ChatFormatting.AQUA));
        }
    }

    private static String fmt(double v) {
        return v < 100 ? String.format(Locale.US, "%.1f", v) : INT.format(Math.round(v));
    }
}
