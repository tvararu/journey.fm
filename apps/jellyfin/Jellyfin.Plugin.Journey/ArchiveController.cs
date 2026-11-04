using System.Security.Cryptography;
using System.Text;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;

namespace Jellyfin.Plugin.Journey;

[ApiController]
[Authorize]
[Route("Journey")]
public class ArchiveController(ILibraryManager library, IUserManager users) : ControllerBase
{
    [HttpGet("Archive")]
    public ActionResult Archive([FromQuery] string ids)
    {
        var user = Guid.TryParse(User.FindFirst("Jellyfin-UserId")?.Value, out var userId)
            ? users.GetUserById(userId)
            : null;
        if (user is null)
        {
            return Forbid();
        }

        var files = new List<(string Name, string Path)>();
        foreach (var id in ids.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            if (!Guid.TryParse(id, out var guid)
                || library.GetItemById(guid) is not Audio track
                || !track.IsVisible(user)
                || !System.IO.File.Exists(track.Path))
            {
                return NotFound(id);
            }

            files.Add((guid.ToString("N"), track.Path));
        }

        var versions = files.Select(f => new FileInfo(f.Path)).ToList();
        var modified = versions.Select(f => f.LastWriteTimeUtc).DefaultIfEmpty(DateTime.UnixEpoch).Max();
        var identity = string.Join('\n', files.Zip(versions, (f, v) => $"{f.Name} {v.Length} {v.LastWriteTimeUtc.Ticks}"));
        var tag = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity)))[..32];
        return File(
            new TarStream(files),
            "application/x-tar",
            new DateTimeOffset(modified),
            new EntityTagHeaderValue($"\"{tag}\""),
            enableRangeProcessing: true);
    }
}
