package dev.nwillis.lens;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/**
 * Live warehouse stock, polled from a published snapshot (JSON object:
 * item id -> count). The warehouse OS pushes this to any raw-file host over
 * CC's HTTP; this mod polls the same URL from the client. That rendezvous is
 * what lets a pure client mod show server-side factory state from anywhere -
 * including standing in the void dimension. Disabled until stockUrl is set.
 */
public final class StockIndex {
    private static final Gson GSON = new Gson();
    private static volatile Map<String, Long> stock = Map.of();
    private static volatile long lastFetchMs = 0;

    public static void start(String url, int pollSeconds) {
        if (url == null || url.isBlank()) return;
        Thread t = new Thread(() -> {
            while (true) {
                try {
                    HttpURLConnection conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
                    conn.setConnectTimeout(10_000);
                    conn.setReadTimeout(20_000);
                    try (InputStreamReader r = new InputStreamReader(
                            conn.getInputStream(), StandardCharsets.UTF_8)) {
                        Map<String, Long> parsed = GSON.fromJson(r,
                            new TypeToken<Map<String, Long>>() {}.getType());
                        if (parsed != null) {
                            stock = parsed;
                            lastFetchMs = System.currentTimeMillis();
                        }
                    }
                } catch (Exception e) {
                    PaperclipLens.LOG.debug("stock poll failed: {}", e.toString());
                }
                try {
                    Thread.sleep(Math.max(15, pollSeconds) * 1000L);
                } catch (InterruptedException e) {
                    return;
                }
            }
        }, "paperclip-lens-stock");
        t.setDaemon(true);
        t.start();
    }

    /** @return warehouse count for the item, or null if unknown/stale/disabled */
    public static Long get(String itemId) {
        if (System.currentTimeMillis() - lastFetchMs > 10 * 60_000) return null;
        return stock.get(itemId);
    }
}
