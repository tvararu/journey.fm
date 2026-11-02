using MediaBrowser.Common.Plugins;

namespace Jellyfin.Plugin.Journey;

public class Plugin : BasePlugin
{
    public Plugin()
    {
        var assembly = GetType().Assembly;
        SetAttributes(assembly.Location, Path.GetDirectoryName(assembly.Location)!, assembly.GetName().Version!);
    }

    public override string Name => "journey.fm";

    public override Guid Id => Guid.Parse("5f0c4a7e-3b9d-4c21-8e6a-9d2b7f1c4e83");

    public override string Description => "Maps the catalogue's tags into Jellyfin's fields.";
}
