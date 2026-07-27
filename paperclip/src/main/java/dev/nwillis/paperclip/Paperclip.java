package dev.nwillis.paperclip;

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

@Mod(Paperclip.MODID)
public final class Paperclip {
    public static final String MODID = "paperclip";

    public static final DeferredRegister.Blocks BLOCKS = DeferredRegister.createBlocks(MODID);
    public static final DeferredRegister.Items ITEMS = DeferredRegister.createItems(MODID);
    public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
        DeferredRegister.create(Registries.BLOCK_ENTITY_TYPE, MODID);

    public static final DeferredHolder<Block, PaperclipTerminalBlock> TERMINAL =
        BLOCKS.register("paperclip_terminal",
            () -> new PaperclipTerminalBlock(BlockBehaviour.Properties.of().strength(2.0f)));

    public static final DeferredHolder<Item, BlockItem> TERMINAL_ITEM =
        ITEMS.register("paperclip_terminal",
            () -> new BlockItem(TERMINAL.get(), new Item.Properties()));

    public static final DeferredHolder<BlockEntityType<?>, BlockEntityType<PaperclipTerminalBlockEntity>> TERMINAL_BE =
        BLOCK_ENTITIES.register("paperclip_terminal",
            () -> BlockEntityType.Builder.of(PaperclipTerminalBlockEntity::new, TERMINAL.get()).build(null));

    // --- GPU compute peripherals (three tiers) + the unobtanium gate ---------
    private static DeferredHolder<Block, GpuBlock> gpu(String name, GpuTier tier) {
        return BLOCKS.register(name,
            () -> new GpuBlock(BlockBehaviour.Properties.of().strength(3.0f), tier));
    }

    public static final DeferredHolder<Block, GpuBlock> GPU_GT1 = gpu("gpu_gt1", GpuTier.GT1);
    public static final DeferredHolder<Block, GpuBlock> GPU_RTX4 = gpu("gpu_rtx4", GpuTier.RTX4);
    public static final DeferredHolder<Block, GpuBlock> GPU_B800 = gpu("gpu_b800", GpuTier.B800);

    public static final DeferredHolder<Item, BlockItem> GPU_GT1_ITEM =
        ITEMS.register("gpu_gt1", () -> new BlockItem(GPU_GT1.get(), new Item.Properties()));
    public static final DeferredHolder<Item, BlockItem> GPU_RTX4_ITEM =
        ITEMS.register("gpu_rtx4", () -> new BlockItem(GPU_RTX4.get(), new Item.Properties()));
    public static final DeferredHolder<Item, BlockItem> GPU_B800_ITEM =
        ITEMS.register("gpu_b800", () -> new BlockItem(GPU_B800.get(), new Item.Properties()));

    public static final DeferredHolder<Item, Item> UNOBTANIUM =
        ITEMS.register("unobtanium", () -> new Item(new Item.Properties().fireResistant()));

    public static final DeferredHolder<BlockEntityType<?>, BlockEntityType<GpuBlockEntity>> GPU_BE =
        BLOCK_ENTITIES.register("gpu", () -> BlockEntityType.Builder.of(
            (pos, state) -> new GpuBlockEntity(pos, state,
                ((GpuBlock) state.getBlock()).tier()),
            GPU_GT1.get(), GPU_RTX4.get(), GPU_B800.get()).build(null));

    public Paperclip(IEventBus modBus) {
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
        event.registerBlockEntity(PeripheralCapability.get(), GPU_BE.get(),
            (be, side) -> be.getPeripheral());
    }

    private void addCreative(BuildCreativeModeTabContentsEvent event) {
        if (event.getTabKey() == CreativeModeTabs.REDSTONE_BLOCKS) {
            event.accept(TERMINAL_ITEM.get());
            event.accept(GPU_GT1_ITEM.get());
            event.accept(GPU_RTX4_ITEM.get());
            event.accept(GPU_B800_ITEM.get());
        }
        if (event.getTabKey() == CreativeModeTabs.INGREDIENTS) {
            event.accept(UNOBTANIUM.get());
        }
    }
}
