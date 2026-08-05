package dev.nwillis.paperclipos;

import net.minecraft.core.BlockPos;
import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.neoforge.network.handling.IPayloadContext;

/** Client -> server: the player clicked an item tile. */
public record OrderPayload(BlockPos pos, String item, int count)
        implements CustomPacketPayload {

    public static final Type<OrderPayload> TYPE = new Type<>(
        ResourceLocation.fromNamespaceAndPath(PaperclipOS.ID, "order"));

    public static final StreamCodec<RegistryFriendlyByteBuf, OrderPayload> CODEC =
        StreamCodec.composite(
            BlockPos.STREAM_CODEC, OrderPayload::pos,
            ByteBufCodecs.STRING_UTF8, OrderPayload::item,
            ByteBufCodecs.VAR_INT, OrderPayload::count,
            OrderPayload::new);

    @Override
    public Type<? extends CustomPacketPayload> type() {
        return TYPE;
    }

    public static void handle(OrderPayload payload, IPayloadContext ctx) {
        ctx.enqueueWork(() -> {
            var level = ctx.player().level();
            if (level.getBlockEntity(payload.pos()) instanceof TerminalBlockEntity be
                    && payload.count() > 0 && payload.count() <= 100000) {
                be.pendingOrders.add(new TerminalBlockEntity.PendingOrder(
                    payload.item(), payload.count(),
                    ctx.player().getName().getString()));
            }
        });
    }
}
