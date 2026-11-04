using System.Text;

namespace Jellyfin.Plugin.Journey;

public static class Tar
{
    private const int Block = 512;

    public static long Length(IEnumerable<long> sizes) =>
        sizes.Sum(size => Block + Padded(size)) + (2 * Block);

    public static async Task Write(Stream output, IEnumerable<(string Name, string Path)> files, CancellationToken cancellation)
    {
        foreach (var (name, path) in files)
        {
            await using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20, useAsync: true);
            await output.WriteAsync(Header(name, input.Length), cancellation);
            await input.CopyToAsync(output, 1 << 20, cancellation);
            await output.WriteAsync(new byte[Padded(input.Length) - input.Length], cancellation);
        }

        await output.WriteAsync(new byte[2 * Block], cancellation);
    }

    public static byte[] Header(string name, long size)
    {
        var header = new byte[Block];
        Encoding.ASCII.GetBytes(name, header);
        Field(header, 100, 8, 0b110_100_100);
        Field(header, 108, 8, 0);
        Field(header, 116, 8, 0);
        Field(header, 124, 12, size);
        Field(header, 136, 12, 0);
        header[156] = (byte)'0';
        Encoding.ASCII.GetBytes("ustar\000", header.AsSpan(257));
        Array.Fill(header, (byte)' ', 148, 8);
        var sum = header.Sum(b => (long)b);
        Encoding.ASCII.GetBytes(Convert.ToString(sum, 8).PadLeft(6, '0') + "\0 ", header.AsSpan(148));
        return header;
    }

    private static long Padded(long size) => (size + Block - 1) / Block * Block;

    private static void Field(byte[] header, int offset, int length, long value) =>
        Encoding.ASCII.GetBytes(Convert.ToString(value, 8).PadLeft(length - 1, '0') + "\0", header.AsSpan(offset));
}
