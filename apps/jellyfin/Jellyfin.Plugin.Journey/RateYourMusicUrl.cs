using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Providers;

namespace Jellyfin.Plugin.Journey;

public class RateYourMusicUrl : IExternalUrlProvider
{
    private const string Prefix = "RYM_URL:";

    public string Name => "Rate Your Music";

    public IEnumerable<string> GetExternalUrls(BaseItem item)
    {
        if (item is not MusicAlbum)
        {
            yield break;
        }

        var tag = item.Tags.FirstOrDefault(t => t.StartsWith(Prefix, StringComparison.Ordinal));
        if (tag is not null)
        {
            yield return tag[Prefix.Length..];
        }
    }
}
