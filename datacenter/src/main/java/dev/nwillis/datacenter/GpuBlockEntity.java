package dev.nwillis.datacenter;

import dan200.computercraft.api.peripheral.IPeripheral;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.entity.BlockEntity;

public final class GpuBlockEntity extends BlockEntity {
    private final GpuTier tier;
    private GpuPeripheral peripheral;

    public GpuBlockEntity(BlockPos pos, BlockState state, GpuTier tier) {
        super(Datacenter.GPU_BE.get(), pos, state);
        this.tier = tier;
    }

    public IPeripheral getPeripheral() {
        if (peripheral == null) peripheral = new GpuPeripheral(tier);
        return peripheral;
    }
}
