package dev.nwillis.paperclip;

import com.mojang.serialization.MapCodec;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.BaseEntityBlock;
import net.minecraft.world.level.block.RenderShape;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;

public final class GpuBlock extends BaseEntityBlock {
    public static final MapCodec<GpuBlock> CODEC = simpleCodec(p -> new GpuBlock(p, GpuTier.GT1));
    private final GpuTier tier;

    public GpuBlock(Properties properties, GpuTier tier) {
        super(properties);
        this.tier = tier;
    }

    public GpuTier tier() {
        return tier;
    }

    @Override
    protected MapCodec<? extends BaseEntityBlock> codec() {
        return CODEC;
    }

    @Override
    public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
        return new GpuBlockEntity(pos, state, tier);
    }

    @Override
    protected RenderShape getRenderShape(BlockState state) {
        return RenderShape.MODEL;
    }
}
