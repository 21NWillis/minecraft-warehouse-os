package dev.nwillis.lens;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Runtime-settable executor tuning - the no-restart decree. Every number
 * the flight-test campaign iterated on lives here, adjustable in-game
 * via {"cmd":"set","key":...,"value":...} order files. Defaults are the
 * values that flew THE FIRST PAPERCLIP 62/62.
 */
public final class Tunables {
    private static final Map<String, Double> V = new ConcurrentHashMap<>();

    static {
        V.put("hoverHeight", 0.85);  // above target center; feet = +1.35
        V.put("approach", 0.9);      // max distance from hover before clicking
        V.put("reach", 3.5);         // face filter (eye to click point)
        V.put("settleTicks", 2.0);   // brake ticks before interacting
        V.put("verifyDelay", 6.0);   // ticks before async verify judges
        V.put("retryLimit", 6.0);    // re-approaches before deferring
        V.put("passLimit", 6.0);     // deferred-queue passes before abandon
        V.put("floor", 1.2);         // min feet height over target base
        V.put("speedMax", 0.9);      // flight speed cap
        V.put("restockKeep", 128.0); // stop pulling from cache at this count
    }

    public static double get(String key) {
        return V.getOrDefault(key, 0.0);
    }

    public static int geti(String key) {
        return (int) Math.round(get(key));
    }

    public static String set(String key, double value) {
        if (!V.containsKey(key)) {
            return "unknown key '" + key + "' - have: " + String.join(", ", V.keySet());
        }
        V.put(key, value);
        return key + " = " + value;
    }

    public static Map<String, Double> all() {
        return V;
    }
}
