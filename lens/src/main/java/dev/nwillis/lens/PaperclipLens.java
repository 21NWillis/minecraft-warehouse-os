package dev.nwillis.lens;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.common.NeoForge;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Paperclip Lens: client-only QoL for the warehouse OS. EMC tooltips from the
 * repo's own emc.txt, live warehouse stock via a published snapshot, and a
 * turtle ESP overlay. Reads the world; changes nothing; needs no server mod.
 */
@Mod(value = PaperclipLens.ID, dist = Dist.CLIENT)
public class PaperclipLens {
    public static final String ID = "paperclip_lens";
    public static final Logger LOG = LoggerFactory.getLogger("paperclip-lens");
    public static LensConfig CONFIG = new LensConfig();

    public PaperclipLens(IEventBus modBus) {
        CONFIG = LensConfig.load(FMLPaths.CONFIGDIR.get());
        EmcIndex.loadAsync(FMLPaths.CONFIGDIR.get(), CONFIG.emcUrl);
        StockIndex.start(CONFIG.stockUrl, CONFIG.stockPollSeconds);

        modBus.addListener(TurtleEsp::registerKeys);
        modBus.addListener(WorldModel::registerKeys);
        modBus.addListener(OrderExecutor::registerKeys);
        modBus.addListener(BlockBlame::registerKeys);
        NeoForge.EVENT_BUS.addListener(ClientCommands::register);
        NeoForge.EVENT_BUS.addListener(TooltipHandler::onTooltip);
        NeoForge.EVENT_BUS.addListener(TurtleEsp::onClientTick);
        NeoForge.EVENT_BUS.addListener(TurtleEsp::onRenderLevel);
        NeoForge.EVENT_BUS.addListener(WorldModel::onClientTick);
        NeoForge.EVENT_BUS.addListener(FieldSnap::onClientTick);
        NeoForge.EVENT_BUS.addListener(ControlOrders::onClientTick);
        NeoForge.EVENT_BUS.addListener(OrderExecutor::onClientTick);
        NeoForge.EVENT_BUS.addListener(OrderExecutor::onRenderLevel);
        NeoForge.EVENT_BUS.addListener(BlockBlame::onClientTick);
        NeoForge.EVENT_BUS.addListener(Telemetry::onClientTick);
        NeoForge.EVENT_BUS.addListener(MaterialsHud::onRenderGui);
        LOG.info("Paperclip Lens up; the factory is watching back");
    }
}
