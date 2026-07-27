package dev.nwillis.datacenter;

import dan200.computercraft.api.peripheral.PeripheralCapability;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.common.Mod;
import net.neoforged.neoforge.capabilities.Capabilities;
import net.neoforged.neoforge.capabilities.RegisterCapabilitiesEvent;
import net.neoforged.neoforge.event.BuildCreativeModeTabContentsEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

@Mod(Datacenter.MODID)
public final class Datacenter {
    public static final String MODID = "datacenter";

    public static final DeferredRegister.Blocks BLOCKS = DeferredRegister.createBlocks(MODID);
    public static final DeferredRegister.Items ITEMS = DeferredRegister.createItems(MODID);
    public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
        DeferredRegister.create(Registries.BLOCK_ENTITY_TYPE, MODID);

    public static final DeferredHolder<Block, DatacenterTerminalBlock> TERMINAL =
        BLOCKS.register("datacenter_terminal",
            () -> new DatacenterTerminalBlock(BlockBehaviour.Properties.of().strength(2.0f)));

    public static final DeferredHolder<Item, BlockItem> TERMINAL_ITEM =
        ITEMS.register("datacenter_terminal",
            () -> new BlockItem(TERMINAL.get(), new Item.Properties()));

    public static final DeferredHolder<BlockEntityType<?>, BlockEntityType<DatacenterTerminalBlockEntity>> TERMINAL_BE =
        BLOCK_ENTITIES.register("datacenter_terminal",
            () -> BlockEntityType.Builder.of(DatacenterTerminalBlockEntity::new, TERMINAL.get()).build(null));

    public Datacenter(IEventBus modBus) {
        BLOCKS.register(modBus);
        ITEMS.register(modBus);
        BLOCK_ENTITIES.register(modBus);
        modBus.addListener(this::registerCapabilities);
        modBus.addListener(this::addCreative);
    }

    private void registerCapabilities(RegisterCapabilitiesEvent event) {
        event.registerBlockEntity(Capabilities.ItemHandler.BLOCK, TERMINAL_BE.get(),
            (be, side) -> be.getItemHandler());
        event.registerBlockEntity(PeripheralCapability.get(), TERMINAL_BE.get(),
            (be, side) -> be.getPeripheral());
    }

    private void addCreative(BuildCreativeModeTabContentsEvent event) {
        if (event.getTabKey() == CreativeModeTabs.REDSTONE_BLOCKS) {
            event.accept(TERMINAL_ITEM.get());
        }
    }
}
