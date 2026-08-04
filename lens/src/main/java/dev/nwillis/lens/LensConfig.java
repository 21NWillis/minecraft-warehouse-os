package dev.nwillis.lens;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Plain-JSON config at config/paperclip_lens.json. No config-lib dependency:
 * this mod should drop into any instance with nothing but NeoForge.
 */
public final class LensConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

    /** Where emc.txt comes from if there's no local cached copy. */
    public String emcUrl =
        "https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/data/emc.txt";
    /**
     * Warehouse stock snapshot endpoint (JSON object: item id -> count).
     * Empty = disabled. The warehouse publishes this via its own HTTP; any
     * raw-file host (gist, pastebin) works.
     */
    public String stockUrl = "";
    public int stockPollSeconds = 60;
    public boolean emcTooltips = true;
    /** Blocks around the player scanned for turtles by the ESP overlay. */
    public int espRadius = 64;
    /** ESP starts enabled? (toggle key works regardless) */
    public boolean espOnByDefault = false;

    /**
     * World model bounds (two [x,y,z] corners, any order). null = the
     * model/journal/snapshot system stays idle. Cover the tower + campus.
     */
    public int[] baseMin = null;
    public int[] baseMax = null;
    /** Dimension the model watches. */
    public String modelDimension = "minecraft:overworld";
    /** Sweep rate: blocks diffed per client tick (20/s). */
    public int sweepBlocksPerTick = 20000;

    public static LensConfig load(Path configDir) {
        Path file = configDir.resolve("paperclip_lens.json");
        try {
            if (Files.exists(file)) {
                return GSON.fromJson(Files.readString(file), LensConfig.class);
            }
        } catch (Exception e) {
            PaperclipLens.LOG.warn("bad config, using defaults: {}", e.toString());
        }
        LensConfig fresh = new LensConfig();
        try {
            Files.createDirectories(configDir);
            Files.writeString(file, GSON.toJson(fresh));
        } catch (IOException ignored) {
        }
        return fresh;
    }
}
