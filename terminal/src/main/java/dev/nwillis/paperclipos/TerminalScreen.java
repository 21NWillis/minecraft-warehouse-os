package dev.nwillis.paperclipos;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.EditBox;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.network.PacketDistributor;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The storefront. Favorites-first item grid with real icons and live
 * stock, instant-filter search, one click = one order at the selected
 * quantity, queue + toast panel on the right. Zero logic beyond
 * presentation: clicks become OrderPayloads, state comes from the BE.
 */
public class TerminalScreen extends Screen {
    private static final Gson GSON = new Gson();
    private static final int CELL = 24;
    private static final int[] QTYS = { 1, 16, 64, 256, 1024 };

    public static class Entry {
        public String id = "";
        public String name = "";
        public double stock = 0;
    }

    public static class QueueLine {
        public String label = "";
        public String status = "";
    }

    public static class Toast {
        public String text = "";
        public boolean ok = true;
    }

    private final TerminalBlockEntity be;
    private EditBox search;
    private int qty = 64;
    private long seenRev = -1;
    private List<Entry> catalog = new ArrayList<>();
    private List<Entry> shown = new ArrayList<>();
    private List<QueueLine> queue = new ArrayList<>();
    private List<Toast> toasts = new ArrayList<>();
    private Map<String, Integer> favs = new HashMap<>();
    private int scroll = 0;
    private String flash = null;
    private long flashUntil = 0;

    // layout, computed in init
    private int panelX, panelY, panelW, panelH, gridX, gridY, gridCols, gridRows, sideX;

    public TerminalScreen(TerminalBlockEntity be) {
        super(Component.literal("Paperclip Terminal"));
        this.be = be;
        loadFavs();
    }

    @Override
    protected void init() {
        panelW = Math.min(width - 20, 480);
        panelH = Math.min(height - 20, 260);
        panelX = (width - panelW) / 2;
        panelY = (height - panelH) / 2;
        sideX = panelX + panelW - 130;
        gridX = panelX + 10;
        gridY = panelY + 42;
        gridCols = (sideX - 10 - gridX) / CELL;
        gridRows = (panelY + panelH - 30 - gridY) / CELL;

        search = new EditBox(font, panelX + 10, panelY + 22, sideX - 20 - panelX, 14,
            Component.literal("search"));
        search.setResponder(text -> {
            scroll = 0;
            refilter();
        });
        search.setHint(Component.literal("search... (or just click a tile)"));
        addRenderableWidget(search);
        setInitialFocus(search);
        refresh(true);
    }

    private void loadFavs() {
        try {
            Path f = FMLPaths.GAMEDIR.get().resolve("paperclipos_favs.json");
            if (Files.exists(f)) {
                favs = GSON.fromJson(Files.readString(f),
                    new TypeToken<Map<String, Integer>>() {}.getType());
                if (favs == null) favs = new HashMap<>();
            }
        } catch (Exception ignored) {
        }
    }

    private void saveFavs() {
        try {
            Files.writeString(FMLPaths.GAMEDIR.get().resolve("paperclipos_favs.json"),
                GSON.toJson(favs));
        } catch (IOException ignored) {
        }
    }

    private void refresh(boolean force) {
        if (!force && be.rev == seenRev) return;
        seenRev = be.rev;
        try {
            List<Entry> parsed = GSON.fromJson(be.catalogJson,
                new TypeToken<List<Entry>>() {}.getType());
            catalog = parsed == null ? new ArrayList<>() : parsed;
            List<QueueLine> q = GSON.fromJson(be.queueJson,
                new TypeToken<List<QueueLine>>() {}.getType());
            queue = q == null ? new ArrayList<>() : q;
            List<Toast> t = GSON.fromJson(be.toastJson,
                new TypeToken<List<Toast>>() {}.getType());
            toasts = t == null ? new ArrayList<>() : t;
        } catch (Exception e) {
            PaperclipOS.LOG.warn("bad terminal state json: {}", e.toString());
        }
        refilter();
    }

    private void refilter() {
        String needle = search == null ? "" : search.getValue().toLowerCase();
        shown = new ArrayList<>();
        for (Entry e : catalog) {
            if (needle.isEmpty() || e.name.toLowerCase().contains(needle)
                || e.id.toLowerCase().contains(needle)) {
                shown.add(e);
            }
        }
        // favorites first (by how often YOU order them), then by stock
        shown.sort(Comparator
            .comparingInt((Entry e) -> -favs.getOrDefault(e.id, 0))
            .thenComparing(e -> -e.stock));
    }

    private ItemStack stackFor(String id) {
        Item item = BuiltInRegistries.ITEM.getOptional(ResourceLocation.tryParse(id))
            .orElse(Items.BARRIER);
        return new ItemStack(item);
    }

    private static String abbrev(double n) {
        if (n >= 1_000_000) return String.format("%.1fm", n / 1_000_000);
        if (n >= 10_000) return String.format("%.0fk", n / 1_000);
        if (n >= 1_000) return String.format("%.1fk", n / 1_000);
        return String.format("%.0f", n);
    }

    @Override
    public void render(GuiGraphics g, int mouseX, int mouseY, float partialTick) {
        refresh(false);
        renderBackground(g, mouseX, mouseY, partialTick);
        // frame
        g.fill(panelX - 2, panelY - 2, panelX + panelW + 2, panelY + panelH + 2, 0xFF9457EB);
        g.fill(panelX, panelY, panelX + panelW, panelY + panelH, 0xF0101018);
        g.drawString(font, "PAPERCLIP TERMINAL", panelX + 10, panelY + 8, 0xFFD8A5FF);
        String stockLine = catalog.size() + " products";
        g.drawString(font, stockLine, sideX, panelY + 8, 0xFF808090);

        // quantity buttons
        int qx = sideX;
        int qy = panelY + 20;
        for (int q : QTYS) {
            String label = q >= 1000 ? (q / 1000) + "k" : String.valueOf(q);
            int w = font.width(label) + 8;
            boolean sel = q == qty;
            g.fill(qx, qy, qx + w, qy + 14, sel ? 0xFF9457EB : 0xFF26263A);
            g.drawString(font, label, qx + 4, qy + 3, sel ? 0xFF101018 : 0xFFB0B0C0);
            qx += w + 3;
        }

        // item grid
        int idx = scroll * gridCols;
        for (int row = 0; row < gridRows; row++) {
            for (int col = 0; col < gridCols; col++) {
                if (idx >= shown.size()) break;
                Entry e = shown.get(idx++);
                int x = gridX + col * CELL;
                int y = gridY + row * CELL;
                boolean hover = mouseX >= x && mouseX < x + CELL - 2
                    && mouseY >= y && mouseY < y + CELL - 2;
                boolean fav = favs.getOrDefault(e.id, 0) > 0;
                g.fill(x, y, x + CELL - 2, y + CELL - 2,
                    hover ? 0xFF3A3A55 : (fav ? 0xFF232338 : 0xFF1A1A28));
                g.renderItem(stackFor(e.id), x + 3, y + 1);
                g.pose().pushPose();
                g.pose().translate(x + 2, y + CELL - 8, 0);
                g.pose().scale(0.6f, 0.6f, 1f);
                g.drawString(font, abbrev(e.stock), 0, 0, 0xFF7FE87F);
                g.pose().popPose();
                if (hover) {
                    g.renderTooltip(font, Component.literal(
                        e.name + "  (" + (long) e.stock + " in stock)  click: craft "
                            + qty), mouseX, mouseY);
                }
            }
        }
        if (shown.size() > gridCols * gridRows) {
            g.drawString(font, "scroll for " + (shown.size() - gridCols * gridRows
                - scroll * gridCols) + " more", gridX, panelY + panelH - 22, 0xFF606070);
        }

        // side panel: queue + toasts
        g.fill(sideX - 4, gridY, sideX - 3, panelY + panelH - 10, 0xFF33334A);
        g.drawString(font, "QUEUE", sideX, gridY, 0xFFD8A5FF);
        int ty = gridY + 12;
        if (queue.isEmpty()) {
            g.drawString(font, "idle", sideX, ty, 0xFF505060);
            ty += 11;
        }
        for (QueueLine ql : queue) {
            if (ty > panelY + panelH - 60) break;
            g.drawString(font, ql.label, sideX, ty, 0xFFE0E0E8);
            g.drawString(font, ql.status, sideX + 6, ty + 10, 0xFF808090);
            ty += 22;
        }
        int by = panelY + panelH - 14;
        for (int i = toasts.size() - 1; i >= 0 && by > ty; i--) {
            Toast t = toasts.get(i);
            g.drawString(font, (t.ok ? "+ " : "! ") + t.text, sideX, by,
                t.ok ? 0xFF7FE87F : 0xFFFF7070);
            by -= 11;
        }

        // local flash
        if (flash != null && System.currentTimeMillis() < flashUntil) {
            g.drawString(font, flash, panelX + 10, panelY + panelH - 12, 0xFFFFD870);
        }
        super.render(g, mouseX, mouseY, partialTick);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        // quantity buttons
        int qx = sideX;
        int qy = panelY + 20;
        for (int q : QTYS) {
            String label = q >= 1000 ? (q / 1000) + "k" : String.valueOf(q);
            int w = font.width(label) + 8;
            if (mouseX >= qx && mouseX < qx + w && mouseY >= qy && mouseY < qy + 14) {
                qty = q;
                return true;
            }
            qx += w + 3;
        }
        // item tiles
        int idx = scroll * gridCols;
        for (int row = 0; row < gridRows; row++) {
            for (int col = 0; col < gridCols; col++) {
                if (idx >= shown.size()) break;
                Entry e = shown.get(idx++);
                int x = gridX + col * CELL;
                int y = gridY + row * CELL;
                if (mouseX >= x && mouseX < x + CELL - 2
                        && mouseY >= y && mouseY < y + CELL - 2) {
                    PacketDistributor.sendToServer(
                        new OrderPayload(be.getBlockPos(), e.id, qty));
                    favs.merge(e.id, 1, Integer::sum);
                    saveFavs();
                    refilter();
                    flash = "queued " + qty + " x " + e.name;
                    flashUntil = System.currentTimeMillis() + 2500;
                    Minecraft.getInstance().player.playSound(
                        net.minecraft.sounds.SoundEvents.UI_BUTTON_CLICK.value(), 0.4f, 1.4f);
                    return true;
                }
            }
        }
        return super.mouseClicked(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double dx, double dy) {
        int maxScroll = Math.max(0, (shown.size() + gridCols - 1) / gridCols - gridRows);
        scroll = Math.max(0, Math.min(maxScroll, scroll - (int) Math.signum(dy)));
        return true;
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }
}
