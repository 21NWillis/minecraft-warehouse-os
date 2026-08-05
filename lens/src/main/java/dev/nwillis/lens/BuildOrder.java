package dev.nwillis.lens;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import net.minecraft.core.BlockPos;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * A parsed build order: named list of placements. File format (written
 * by the dev-side tooling, e.g. tools/plan2order.lua):
 *   { "name": "gun row", "origin": [x,y,z] (optional, default absolute),
 *     "blocks": [ {"x":1,"y":0,"z":4,"b":"minecraft:deepslate"}, ... ] }
 * If "origin" is present, block coords are relative to it; otherwise
 * they are absolute world coordinates. Alternatively "fromDatum":
 * [dx,dy,dz] anchors the order at the /datum position plus that offset -
 * the preferred form, since orders then never carry world coordinates.
 */
public final class BuildOrder {
    public record Placement(BlockPos pos, String block) {}

    public final String name;
    public final List<Placement> placements;

    private BuildOrder(String name, List<Placement> placements) {
        this.name = name;
        this.placements = placements;
    }

    public static BuildOrder load(Path file) throws Exception {
        JsonObject root = new Gson().fromJson(Files.readString(file), JsonObject.class);
        String name = root.has("name") ? root.get("name").getAsString()
            : file.getFileName().toString();
        int ox = 0, oy = 0, oz = 0;
        if (root.has("fromDatum")) {
            int[] d = PaperclipLens.CONFIG.datum;
            if (d == null) {
                throw new Exception(
                    "order uses fromDatum but no datum is set - run /datum on it");
            }
            JsonArray o = root.getAsJsonArray("fromDatum");
            ox = d[0] + o.get(0).getAsInt();
            oy = d[1] + o.get(1).getAsInt();
            oz = d[2] + o.get(2).getAsInt();
        } else if (root.has("origin")) {
            JsonArray o = root.getAsJsonArray("origin");
            ox = o.get(0).getAsInt();
            oy = o.get(1).getAsInt();
            oz = o.get(2).getAsInt();
        }
        List<Placement> out = new ArrayList<>();
        for (JsonElement e : root.getAsJsonArray("blocks")) {
            JsonObject b = e.getAsJsonObject();
            out.add(new Placement(new BlockPos(
                ox + b.get("x").getAsInt(),
                oy + b.get("y").getAsInt(),
                oz + b.get("z").getAsInt()),
                b.get("b").getAsString()));
        }
        // build bottom-up, then in scanline order - keeps support below
        // and the flight path coherent
        out.sort(Comparator
            .comparingInt((Placement p) -> p.pos().getY())
            .thenComparingInt(p -> p.pos().getZ())
            .thenComparingInt(p -> p.pos().getX()));
        return new BuildOrder(name, out);
    }
}
