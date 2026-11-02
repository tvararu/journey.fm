using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Providers;

namespace Jellyfin.Plugin.Journey;

public class AlbumProvider(AlbumTags albumTags) : ICustomMetadataProvider<MusicAlbum>, IHasItemChangeMonitor
{
    public string Name => "journey.fm album tags";

    public bool HasChanged(BaseItem item, IDirectoryService directoryService) => true;

    public Task<ItemUpdateType> FetchAsync(MusicAlbum item, MetadataRefreshOptions options, CancellationToken cancellationToken)
    {
        var fields = TagMapping.Map(albumTags.ForAlbum(item)).Album;
        var changed = Apply.Fields(item, fields, TagMapping.AlbumProviderIds);
        if (item.CommunityRating != fields.CommunityRating)
        {
            item.CommunityRating = fields.CommunityRating;
            changed = true;
        }

        return Task.FromResult(changed ? ItemUpdateType.MetadataEdit : ItemUpdateType.None);
    }
}
