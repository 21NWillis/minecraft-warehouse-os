package dev.nwillis.paperclip;

/**
 * GPU tiers. Balance levers: maxElements = "VRAM" (largest problem it will
 * accept), opsPerTick = a soft budget so a heavy kernel can't monopolize the
 * server main thread (the good-citizen rule, as a hardware spec). Higher tiers
 * cost exponentially more to craft; the B800 needs unobtanium.
 */
public enum GpuTier {
    GT1("GT-1", 1_024, 5_000_000L),
    RTX4("RTX-4", 65_536, 250_000_000L),
    B800("B800", 1_048_576, 20_000_000_000L);

    public final String label;
    public final int maxElements;
    public final long opsPerTick;

    GpuTier(String label, int maxElements, long opsPerTick) {
        this.label = label;
        this.maxElements = maxElements;
        this.opsPerTick = opsPerTick;
    }
}
