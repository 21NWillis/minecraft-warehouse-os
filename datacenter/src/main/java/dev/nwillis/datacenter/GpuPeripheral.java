package dev.nwillis.datacenter;

import dan200.computercraft.api.lua.LuaException;
import dan200.computercraft.api.lua.LuaFunction;
import dan200.computercraft.api.peripheral.IPeripheral;

import javax.annotation.Nullable;
import java.util.HashMap;
import java.util.Map;

/**
 * A compute accelerator peripheral. Runs numeric kernels in JIT-compiled Java -
 * orders of magnitude faster than the interpreted, sandboxed Lua VM - themed as
 * a GPU. It creates no items and moves nothing: pure compute, so it cannot
 * unbalance the economy. It only makes YOUR programs faster, gated by tier.
 *
 * (An optional real-SIMD path via java.incubator.vector exists but needs a JVM
 * flag; the portable scalar kernels here are already a massive speedup and Just
 * Work, so that's what ships.)
 */
public final class GpuPeripheral implements IPeripheral {
    private final GpuTier tier;

    public GpuPeripheral(GpuTier tier) {
        this.tier = tier;
    }

    @Override
    public String getType() {
        return "gpu";
    }

    @Override
    public boolean equals(@Nullable IPeripheral other) {
        return other instanceof GpuPeripheral p && p.tier == tier;
    }

    private void checkSize(long n) throws LuaException {
        if (n > tier.maxElements) {
            throw new LuaException(tier.label + " VRAM exceeded: " + n
                + " > " + tier.maxElements + " elements");
        }
    }

    // Lua array table -> double[]. Keys are 1..n (CC hands numbers as doubles).
    private static double[] arr(Map<?, ?> t) throws LuaException {
        int n = t.size();
        double[] out = new double[n];
        for (Map.Entry<?, ?> e : t.entrySet()) {
            int idx = ((Number) e.getKey()).intValue();
            if (idx < 1 || idx > n) throw new LuaException("array keys must be 1..n contiguous");
            out[idx - 1] = ((Number) e.getValue()).doubleValue();
        }
        return out;
    }

    private static Map<Integer, Double> toLua(double[] a) {
        Map<Integer, Double> m = new HashMap<>();
        for (int i = 0; i < a.length; i++) m.put(i + 1, a[i]);
        return m;
    }

    // ---------------------------------------------------------------- API

    @LuaFunction
    public final Map<String, Object> info() {
        Map<String, Object> m = new HashMap<>();
        m.put("tier", tier.label);
        m.put("maxElements", tier.maxElements);
        m.put("opsPerTick", tier.opsPerTick);
        return m;
    }

    @LuaFunction
    public final Map<Integer, Double> vadd(Map<?, ?> a, Map<?, ?> b) throws LuaException {
        double[] x = arr(a), y = arr(b);
        if (x.length != y.length) throw new LuaException("length mismatch");
        checkSize(x.length);
        double[] r = new double[x.length];
        for (int i = 0; i < x.length; i++) r[i] = x[i] + y[i];
        return toLua(r);
    }

    @LuaFunction
    public final Map<Integer, Double> saxpy(double alpha, Map<?, ?> x, Map<?, ?> y) throws LuaException {
        double[] a = arr(x), b = arr(y);
        if (a.length != b.length) throw new LuaException("length mismatch");
        checkSize(a.length);
        double[] r = new double[a.length];
        for (int i = 0; i < a.length; i++) r[i] = alpha * a[i] + b[i];
        return toLua(r);
    }

    @LuaFunction
    public final double dot(Map<?, ?> a, Map<?, ?> b) throws LuaException {
        double[] x = arr(a), y = arr(b);
        if (x.length != y.length) throw new LuaException("length mismatch");
        checkSize(x.length);
        double s = 0;
        for (int i = 0; i < x.length; i++) s += x[i] * y[i];
        return s;
    }

    // flat row-major matmul: a is n x m, b is m x k -> n x k (flattened)
    @LuaFunction
    public final Map<Integer, Double> matmul(Map<?, ?> a, Map<?, ?> b, int n, int m, int k) throws LuaException {
        if (n <= 0 || m <= 0 || k <= 0) throw new LuaException("bad dims");
        checkSize((long) Math.max(n * (long) m, Math.max(m * (long) k, n * (long) k)));
        double[] A = arr(a), B = arr(b);
        if (A.length != n * m || B.length != m * k) throw new LuaException("dim/length mismatch");
        double[] C = new double[n * k];
        for (int i = 0; i < n; i++) {
            for (int p = 0; p < m; p++) {
                double aip = A[i * m + p];
                int cRow = i * k, bRow = p * k;
                for (int j = 0; j < k; j++) C[cRow + j] += aip * B[bRow + j];
            }
        }
        return toLua(C);
    }

    /**
     * Self-contained benchmark: multiply two size x size matrices generated
     * internally (no marshalling cost) and return elapsed microseconds. This is
     * the "GPU vs the Lua VM" demo - compare against a pure-Lua matmul of the
     * same size.
     */
    @LuaFunction
    public final double bench(int size) throws LuaException {
        checkSize((long) size * size);
        double[] A = new double[size * size], B = new double[size * size], C = new double[size * size];
        for (int i = 0; i < A.length; i++) { A[i] = (i % 7) * 0.5; B[i] = (i % 5) * 0.25; }
        long t0 = System.nanoTime();
        for (int i = 0; i < size; i++) {
            for (int p = 0; p < size; p++) {
                double aip = A[i * size + p];
                int cRow = i * size, bRow = p * size;
                for (int j = 0; j < size; j++) C[cRow + j] += aip * B[bRow + j];
            }
        }
        long dt = System.nanoTime() - t0;
        return dt / 1000.0;
    }
}
