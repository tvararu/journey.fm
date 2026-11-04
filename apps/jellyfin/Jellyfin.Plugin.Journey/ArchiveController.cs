using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.Journey;

[ApiController]
[Authorize]
[Route("Journey")]
public class ArchiveController(ILibraryManager library, IUserManager users) : ControllerBase
{
    [HttpGet("Archive")]
    public async Task<ActionResult> Archive([FromQuery] string ids, CancellationToken cancellation)
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

        Response.ContentType = "application/x-tar";
        Response.ContentLength = Tar.Length(files.Select(f => new FileInfo(f.Path).Length));
        await Tar.Write(Response.Body, files, cancellation);
        return new EmptyResult();
    }
}
