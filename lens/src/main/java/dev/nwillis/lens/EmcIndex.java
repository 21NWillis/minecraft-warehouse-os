package dev.nwillis.lens;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/**
 * The Paperclip Exchange price index: item id -> EMC value, parsed from the
 * warehouse repo's emc.txt ("modid:item 123.00" per line). Loads from a local
 * cache under config/, else fetches from GitHub raw once and caches. All off
 * the render thread; lookups are just a HashMap read.
 */
public final class EmcIndex {
    private static volatile Map<String, Double> values = Map.of();

    public static void loadAsync(Path configDir, String url) {
        Thread t = new Thread(() -> load(configDir, url), "paperclip-lens-emc");
        t.setDaemon(true);
        t.start();
    }

    private static void load(Path configDir, String url) {
        Path cache = configDir.resolve("paperclip_lens").resolve("emc.txt");
        try {
            if (!Files.exists(cache)) {
                PaperclipLens.LOG.info("fetching emc.txt from {}", url);
                HttpURLConnection conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
                conn.setConnectTimeout(10_000);
                conn.setReadTimeout(30_000);
                byte[] body = conn.getInputStream().readAllBytes();
                Files.createDirectories(cache.getParent());
                Files.write(cache, body);
            }
            Map<String, Double> parsed = new HashMap<>(32_000);
            try (BufferedReader r = new BufferedReader(new InputStreamReader(
                    Files.newInputStream(cache), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                    int sp = line.lastIndexOf(' ');
                    if (sp <= 0) continue;
                    String id = line.substring(0, sp).trim();
                    if (id.isEmpty()) continue;
                    try {
                        parsed.put(id, Double.parseDouble(line.substring(sp + 1)));
                    } catch (NumberFormatException ignored) {
                    }
                }
            }
            values = parsed;
            PaperclipLens.LOG.info("EMC index ready: {} items", parsed.size());
        } catch (Exception e) {
            PaperclipLens.LOG.warn("EMC index unavailable: {}", e.toString());
        }
    }

    /** @return EMC per item, or null if unpriced/not loaded yet */
    public static Double get(String itemId) {
        return values.get(itemId);
    }

    public static boolean ready() {
        return !values.isEmpty();
    }
}
