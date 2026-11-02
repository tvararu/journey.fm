using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Providers;

namespace Jellyfin.Plugin.Journey;

public class ArtistProvider(AlbumTags albumTags, ILibraryManager libraryManager)
    : ICustomMetadataProvider<MusicArtist>, IHasItemChangeMonitor
{
    public string Name => "journey.fm artist tags";

    public bool HasChanged(BaseItem item, IDirectoryService directoryService) => true;

    public Task<ItemUpdateType> FetchAsync(MusicArtist item, MetadataRefreshOptions options, CancellationToken cancellationToken)
    {
        var albums = libraryManager.GetItemList(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.MusicAlbum],
                AlbumArtistIds = [item.Id],
                Recursive = true,
            })
            .OfType<MusicAlbum>()
            .OrderBy(a => a.SortName, StringComparer.Ordinal);
        var sort = TagMapping.AlbumArtistSort(albums.Select(albumTags.ForAlbum));
        if (string.Equals(item.ForcedSortName ?? string.Empty, sort ?? string.Empty, StringComparison.Ordinal))
        {
            return Task.FromResult(ItemUpdateType.None);
        }

        item.ForcedSortName = sort;
        return Task.FromResult(ItemUpdateType.MetadataEdit);
    }
}
