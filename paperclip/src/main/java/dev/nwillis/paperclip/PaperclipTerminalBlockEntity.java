package dev.nwillis.paperclip;

import dan200.computercraft.api.peripheral.IPeripheral;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.neoforge.items.ItemStackHandler;

public final class PaperclipTerminalBlockEntity extends BlockEntity {
    private final ItemStackHandler items = new ItemStackHandler(9) {
        @Override
        protected void onContentsChanged(int slot) {
            setChanged();
        }
    };
    private PaperclipPeripheral peripheral;

    public PaperclipTerminalBlockEntity(BlockPos pos, BlockState state) {
        super(Paperclip.TERMINAL_BE.get(), pos, state);
    }

    public ItemStackHandler getItemHandler() {
        return items;
    }

    public IPeripheral getPeripheral() {
        if (peripheral == null) peripheral = new PaperclipPeripheral(this);
        return peripheral;
    }

    @Override
    protected void saveAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.saveAdditional(tag, registries);
        tag.put("Items", items.serializeNBT(registries));
    }

    @Override
    protected void loadAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.loadAdditional(tag, registries);
        if (tag.contains("Items")) {
            items.deserializeNBT(registries, tag.getCompound("Items"));
        }
    }
}
