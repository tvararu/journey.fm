using System.Diagnostics;
using Xunit;

namespace Jellyfin.Plugin.Journey.Tests;

public class TarTests
{
    private static readonly int[] Sizes = [0, 1, 511, 512, 513, 70_000];

    private static List<(string Name, string Path)> Files(string directory) =>
        Sizes.Select((size, i) =>
        {
            var path = Path.Combine(directory, $"in{i}");
            File.WriteAllBytes(path, Enumerable.Range(0, size).Select(b => (byte)((b * 7) + i)).ToArray());
            return ($"{i:x32}", path);
        }).ToList();

    [Fact]
    public async Task SystemTarExtractsWhatWasStreamed()
    {
        var directory = Directory.CreateTempSubdirectory().FullName;
        var files = Files(directory);
        var archive = Path.Combine(directory, "out.tar");
        await using (var output = File.Create(archive))
        await using (var tar = new TarStream(files))
        {
            await tar.CopyToAsync(output, TestContext.Current.CancellationToken);
            Assert.Equal(tar.Length, output.Length);
        }

        var extracted = Directory.CreateDirectory(Path.Combine(directory, "out")).FullName;
        using var process = Process.Start(new ProcessStartInfo("tar", ["-xf", archive, "-C", extracted]) { RedirectStandardError = true })!;
        var error = await process.StandardError.ReadToEndAsync(TestContext.Current.CancellationToken);
        await process.WaitForExitAsync(TestContext.Current.CancellationToken);
        Assert.Equal((0, ""), (process.ExitCode, error));
        foreach (var (name, path) in files)
        {
            Assert.Equal(File.ReadAllBytes(path), File.ReadAllBytes(Path.Combine(extracted, name)));
        }
    }

    [Fact]
    public void ReadingFromAnyOffsetMatchesTheWholeArchive()
    {
        var files = Files(Directory.CreateTempSubdirectory().FullName);
        using var whole = new MemoryStream();
        using (var tar = new TarStream(files))
        {
            tar.CopyTo(whole);
        }

        foreach (var offset in new long[] { 0, 1, 511, 512, 1024, 1025, 3000, 70_000, whole.Length - 1 })
        {
            using var tar = new TarStream(files);
            tar.Seek(offset, SeekOrigin.Begin);
            using var rest = new MemoryStream();
            tar.CopyTo(rest);
            Assert.Equal(whole.ToArray()[(int)offset..], rest.ToArray());
        }
    }
}
