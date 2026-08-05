package dev.nwillis.paperclipos;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.protocol.game.ClientboundBlockEntityDataPacket;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

/**
 * State holder + sync. The CC peripheral writes catalog/queue/toast
 * JSON in (server side), vanilla BE data sync carries it to every
 * viewer, and the screen renders straight from the client copy.
 * Player clicks land in pendingOrders for the peripheral to drain.
 */
public class TerminalBlockEntity extends BlockEntity {
    public record PendingOrder(String item, int count, String player) {}

    public String catalogJson = "[]";
    public String queueJson = "[]";
    public String toastJson = "[]";
    public long rev = 0;

    // server side only; drained by the CC peripheral
    public final List<PendingOrder> pendingOrders = new ArrayList<>();
    // rolling toast log (server-authoritative)
    public final Deque<String> toasts = new ArrayDeque<>();

    public TerminalBlockEntity(BlockPos pos, BlockState state) {
        super(PaperclipOS.TERMINAL_BE.get(), pos, state);
    }

    /** Server side: mutate then broadcast to viewers. */
    public void push() {
        rev++;
        setChanged();
        if (level != null && !level.isClientSide) {
            level.sendBlockUpdated(worldPosition, getBlockState(), getBlockState(), 3);
        }
    }

    public void addToast(String json) {
        toasts.addLast(json);
        while (toasts.size() > 8) toasts.removeFirst();
        toastJson = "[" + String.join(",", toasts) + "]";
        push();
    }

    @Override
    protected void saveAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.saveAdditional(tag, registries);
        tag.putString("catalog", catalogJson);
        tag.putString("queue", queueJson);
        tag.putString("toasts", toastJson);
        tag.putLong("rev", rev);
    }

    @Override
    protected void loadAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.loadAdditional(tag, registries);
        catalogJson = tag.getString("catalog");
        queueJson = tag.getString("queue");
        toastJson = tag.getString("toasts");
        rev = tag.getLong("rev");
        if (catalogJson.isEmpty()) catalogJson = "[]";
        if (queueJson.isEmpty()) queueJson = "[]";
        if (toastJson.isEmpty()) toastJson = "[]";
    }

    @Override
    public CompoundTag getUpdateTag(HolderLookup.Provider registries) {
        return saveWithoutMetadata(registries);
    }

    @Override
    public ClientboundBlockEntityDataPacket getUpdatePacket() {
        return ClientboundBlockEntityDataPacket.create(this);
    }
}
