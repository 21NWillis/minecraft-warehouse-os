package dev.nwillis.paperclipos;

import dan200.computercraft.api.peripheral.PeripheralCapability;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.common.Mod;
import net.neoforged.neoforge.capabilities.RegisterCapabilitiesEvent;
import net.neoforged.neoforge.event.BuildCreativeModeTabContentsEvent;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.registries.DeferredBlock;
import net.neoforged.neoforge.registries.DeferredRegister;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.function.Supplier;

/**
 * PaperclipOS Terminal: a real ordering UI for the warehouse crafting
 * fleet. The GUI is only the face - a CC computer wraps the terminal as
 * a peripheral, pushes catalog/queue state in, and drains player orders
 * out. All planning stays in Lua where it belongs.
 */
@Mod(PaperclipOS.ID)
public class PaperclipOS {
    public static final String ID = "paperclipos";
    public static final Logger LOG = LoggerFactory.getLogger("paperclipos");

    public static final DeferredRegister.Blocks BLOCKS = DeferredRegister.createBlocks(ID);
    public static final DeferredRegister.Items ITEMS = DeferredRegister.createItems(ID);
    public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
        DeferredRegister.create(Registries.BLOCK_ENTITY_TYPE, ID);

    public static final DeferredBlock<Block> TERMINAL = BLOCKS.registerBlock("terminal",
        TerminalBlock::new, BlockBehaviour.Properties.of().strength(1.5f));
    public static final Supplier<BlockEntityType<TerminalBlockEntity>> TERMINAL_BE =
        BLOCK_ENTITIES.register("terminal", () ->
            BlockEntityType.Builder.of(TerminalBlockEntity::new, TERMINAL.get()).build(null));

    static {
        ITEMS.registerSimpleBlockItem("terminal", TERMINAL);
    }

    public PaperclipOS(IEventBus modBus) {
        BLOCKS.register(modBus);
        ITEMS.register(modBus);
        BLOCK_ENTITIES.register(modBus);
        modBus.addListener(this::registerCapabilities);
        modBus.addListener(this::registerPayloads);
        modBus.addListener(this::addCreative);
        LOG.info("PaperclipOS Terminal up; the storefront is open");
    }

    private void registerCapabilities(RegisterCapabilitiesEvent event) {
        event.registerBlockEntity(PeripheralCapability.get(), TERMINAL_BE.get(),
            (be, side) -> new TerminalPeripheral(be));
    }

    private void registerPayloads(RegisterPayloadHandlersEvent event) {
        var registrar = event.registrar("1");
        registrar.playToServer(OrderPayload.TYPE, OrderPayload.CODEC, OrderPayload::handle);
    }

    private void addCreative(BuildCreativeModeTabContentsEvent event) {
        if (event.getTabKey() == CreativeModeTabs.FUNCTIONAL_BLOCKS) {
            event.accept(TERMINAL);
        }
    }
}
