using System.Text;

namespace Jellyfin.Plugin.Journey;

public sealed class TarStream : Stream
{
    private const int Block = 512;

    private readonly List<(long Start, long Length, byte[]? Bytes, string? Path)> _segments = [];
    private readonly long _length;
    private FileStream? _file;
    private string? _filePath;
    private long _position;

    public TarStream(IEnumerable<(string Name, string Path)> files)
    {
        foreach (var (name, path) in files)
        {
            var size = new FileInfo(path).Length;
            Add(Block, Header(name, size), null);
            Add(size, null, path);
            Add(((size + Block - 1) / Block * Block) - size, null, null);
        }

        Add(2 * Block, null, null);
        _length = _segments[^1].Start + _segments[^1].Length;
    }

    public override bool CanRead => true;

    public override bool CanSeek => true;

    public override bool CanWrite => false;

    public override long Length => _length;

    public override long Position
    {
        get => _position;
        set => _position = Math.Clamp(value, 0, _length);
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

    public override int Read(byte[] buffer, int offset, int count) => Read(buffer.AsSpan(offset, count));

    public override int Read(Span<byte> buffer)
    {
        var total = 0;
        while (buffer.Length > 0 && _position < _length)
        {
            var (start, length, bytes, path) = _segments.First(s => _position < s.Start + s.Length);
            var within = _position - start;
            var count = (int)Math.Min(buffer.Length, length - within);
            if (bytes is not null)
            {
                bytes.AsSpan((int)within, count).CopyTo(buffer);
            }
            else if (path is null)
            {
                buffer[..count].Clear();
            }
            else
            {
                count = ReadFile(path, within, buffer[..count]);
            }

            _position += count;
            total += count;
            buffer = buffer[count..];
        }

        return total;
    }

    public override long Seek(long offset, SeekOrigin origin) =>
        Position = origin switch
        {
            SeekOrigin.Begin => offset,
            SeekOrigin.Current => _position + offset,
            _ => _length + offset,
        };

    public override void Flush()
    {
    }

    public override void SetLength(long value) => throw new NotSupportedException();

    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _file?.Dispose();
        }

        base.Dispose(disposing);
    }

    private static void Field(byte[] header, int offset, int length, long value) =>
        Encoding.ASCII.GetBytes(Convert.ToString(value, 8).PadLeft(length - 1, '0') + "\0", header.AsSpan(offset));

    private void Add(long length, byte[]? bytes, string? path)
    {
        if (length > 0)
        {
            _segments.Add((_segments.Count == 0 ? 0 : _segments[^1].Start + _segments[^1].Length, length, bytes, path));
        }
    }

    private int ReadFile(string path, long offset, Span<byte> buffer)
    {
        if (_filePath != path)
        {
            _file?.Dispose();
            _file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16);
            _filePath = path;
        }

        _file!.Position = offset;
        var read = _file.Read(buffer);
        return read > 0 ? read : throw new EndOfStreamException(path);
    }
}
