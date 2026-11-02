using MediaBrowser.Controller.Entities;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.Journey;

internal static class Apply
{
    public static bool Fields(BaseItem item, ItemFields fields, IEnumerable<string> ownedProviderIds)
    {
        var changed = false;
        var tags = TagMapping.MergeTags(item.Tags, fields.Tags);
        if (!tags.SequenceEqual(item.Tags, StringComparer.Ordinal))
        {
            item.Tags = tags;
            changed = true;
        }

        foreach (var key in ownedProviderIds)
        {
            fields.ProviderIds.TryGetValue(key, out var want);
            if (string.Equals(item.GetProviderId(key), want, StringComparison.Ordinal))
            {
                continue;
            }

            if (want is null)
            {
                item.RemoveProviderId(key);
            }
            else
            {
                item.SetProviderId(key, want);
            }

            changed = true;
        }

        if (fields.PremiereDate is { } date && (item.PremiereDate != date || item.ProductionYear != date.Year))
        {
            item.PremiereDate = date;
            item.ProductionYear = date.Year;
            changed = true;
        }

        return changed;
    }
}
