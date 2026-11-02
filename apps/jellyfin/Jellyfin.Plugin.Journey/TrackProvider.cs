using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Providers;

namespace Jellyfin.Plugin.Journey;

public class TrackProvider(AlbumTags albumTags, ILibraryManager libraryManager)
    : ICustomMetadataProvider<Audio>, IHasItemChangeMonitor
{
    private static readonly HashSet<PersonKind> CreditKinds =
        TagMapping.Credits.Values.Select(k => Enum.Parse<PersonKind>(k)).ToHashSet();

    public string Name => "journey.fm track tags";

    public bool HasChanged(BaseItem item, IDirectoryService directoryService)
    {
        var file = string.IsNullOrEmpty(item.Path) ? null : directoryService.GetFile(item.Path);
        return file is not null && item.HasChanged(file.LastWriteTimeUtc);
    }

    public Task<ItemUpdateType> FetchAsync(Audio item, MetadataRefreshOptions options, CancellationToken cancellationToken)
    {
        var fields = Fields(item) ?? new ItemFields();
        var changed = Apply.Fields(item, fields, TagMapping.TrackProviderIds);
        changed |= ApplyPeople(item, fields.People);
        return Task.FromResult(changed ? ItemUpdateType.MetadataEdit : ItemUpdateType.None);
    }

    private ItemFields? Fields(Audio item)
    {
        var album = item.AlbumEntity;
        if (album is not null)
        {
            return TagMapping.Map(albumTags.ForAlbum(album)).Tracks.GetValueOrDefault(item.Path);
        }

        var own = albumTags.Read(item.Path);
        return own is null ? null : TagMapping.MapAlone(new TrackTags(item.Path, own));
    }

    private bool ApplyPeople(Audio item, IReadOnlyList<Credit> credits)
    {
        var existing = libraryManager.GetPeople(item);
        var next = existing.Where(p => !CreditKinds.Contains(p.Type))
            .Concat(credits.Select(c => new PersonInfo { Name = c.Name, Type = Enum.Parse<PersonKind>(c.Kind) }))
            .ToList();
        if (existing.Select(Key).SequenceEqual(next.Select(Key)))
        {
            return false;
        }

        libraryManager.UpdatePeople(item, next);
        return true;
    }

    private static (string, PersonKind, string?) Key(PersonInfo person) => (person.Name, person.Type, person.Role);
}
