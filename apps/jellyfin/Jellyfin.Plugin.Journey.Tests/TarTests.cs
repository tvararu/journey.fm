using System.Diagnostics;
using Xunit;

namespace Jellyfin.Plugin.Journey.Tests;

public class TarTests
{
    [Fact]
    public async Task SystemTarExtractsWhatWasWritten()
    {
        var directory = Directory.CreateTempSubdirectory().FullName;
        var sizes = new[] { 0, 1, 511, 512, 513, 70_000 };
        var files = sizes.Select((size, i) =>
        {
            var path = Path.Combine(directory, $"in{i}");
            File.WriteAllBytes(path, Enumerable.Range(0, size).Select(b => (byte)(b * 7 + i)).ToArray());
            return ($"{i:x32}", path);
        }).ToList();
        var archive = Path.Combine(directory, "out.tar");
        await using (var output = File.Create(archive))
        {
            await Tar.Write(output, files, CancellationToken.None);
        }

        Assert.Equal(Tar.Length(sizes.Select(s => (long)s)), new FileInfo(archive).Length);
        var extracted = Directory.CreateDirectory(Path.Combine(directory, "out")).FullName;
        using var tar = Process.Start(new ProcessStartInfo("tar", ["-xf", archive, "-C", extracted]) { RedirectStandardError = true })!;
        var error = await tar.StandardError.ReadToEndAsync(TestContext.Current.CancellationToken);
        await tar.WaitForExitAsync(TestContext.Current.CancellationToken);
        Assert.Equal((0, ""), (tar.ExitCode, error));
        foreach (var (name, path) in files)
        {
            Assert.Equal(File.ReadAllBytes(path), File.ReadAllBytes(Path.Combine(extracted, name)));
        }
    }
}
