using System.IO.Compression;
using System.Text;

// icongen — generate a distinct icon per language for the dotnetcompilers toolchain.
// Each icon is a colored tile with a short label drawn in an embedded 8x8 font, written
// as a 256x256 RGBA PNG into <repo>\icons\. cc embeds these into the .exe it produces.
//
//   dotnet run --project src/icongen            (writes <repo>\icons\*.png)

internal static class Program
{
    const int N = 256;                 // canvas size

    static int Main()
    {
        string repo = FindRepo();
        string dir = Path.Combine(repo, "icons");
        Directory.CreateDirectory(dir);

        // (key, label, background, foreground) — color is redolent of each language
        var langs = new (string key, string label, (int, int, int) bg, (int, int, int) fg)[]
        {
            ("default",  "C",   (0x37,0x6B,0xA8), (255,255,255)),   // the C compiler itself
            ("pascal",   "P",   (0x12,0x3A,0x8E), (255,255,255)),   // Turbo blue
            ("oberon",   "M2",  (0x2A,0x8A,0x8A), (255,255,255)),
            ("tcpp",     "C++", (0x4E,0x86,0xC6), (255,255,255)),
            ("qbasic",   "QB",  (0x2B,0x57,0xA6), (255,255,255)),
            ("forth",    "FH",  (0x1E,0x7A,0x44), (0xCF,0xFF,0xDF)),
            ("fortran",  "F",   (0x5B,0x3A,0x9E), (255,255,255)),
            ("cobol",    "CB",  (0x12,0x7A,0x2E), (255,255,255)),   // mainframe green
            ("coil",     "CL",  (0x55,0x5A,0x66), (255,255,255)),
            ("logo",     "LG",  (0x33,0x9A,0x33), (255,255,255)),   // turtle green
            ("lisp",     "LI",  (0x6E,0x3A,0xA0), (255,255,255)),   // parens purple
            ("prolog",   "PL",  (0xC8,0x6A,0x14), (255,255,255)),
            ("bc",       "BC",  (0x1F,0x6B,0x6B), (255,255,255)),
            ("ada",      "A",   (0x12,0x7A,0x44), (255,255,255)),
            ("smalltalk","ST",  (0x33,0x6B,0xC0), (255,255,255)),
            ("lua",      "LU",  (0x22,0x22,0x8C), (255,255,255)),   // moon blue
            ("awk",      "AK",  (0xC2,0x52,0x12), (255,255,255)),
        };

        foreach (var (key, label, bg, fg) in langs)
        {
            byte[] rgba = RenderTile(label, bg, fg);
            byte[] png = EncodePng(N, N, rgba);
            string path = Path.Combine(dir, key + ".png");
            File.WriteAllBytes(path, png);
            Console.WriteLine($"  {path}  ({label})");
        }
        Console.WriteLine($"generated {langs.Length} icons in {dir}");
        return 0;
    }

    static string FindRepo()
    {
        string d = AppContext.BaseDirectory;
        for (int i = 0; i < 10 && d != null; i++)
        {
            if (File.Exists(Path.Combine(d, "build_all.sh"))) return d;
            d = Path.GetDirectoryName(d.TrimEnd('\\', '/'))!;
        }
        return Directory.GetCurrentDirectory();
    }

    // ---- tile rendering ----
    static byte[] RenderTile(string label, (int r, int g, int b) bg, (int r, int g, int b) fg)
    {
        var px = new byte[N * N * 4];
        void Set(int x, int y, int r, int g, int b)
        {
            if ((uint)x >= N || (uint)y >= N) return;
            int i = (y * N + x) * 4; px[i] = (byte)r; px[i + 1] = (byte)g; px[i + 2] = (byte)b; px[i + 3] = 255;
        }
        // background fill
        for (int y = 0; y < N; y++) for (int x = 0; x < N; x++) Set(x, y, bg.r, bg.g, bg.b);
        // a darker rounded-ish border frame for definition
        int dr = bg.r * 6 / 10, dg = bg.g * 6 / 10, db = bg.b * 6 / 10;
        for (int t = 0; t < 10; t++)
            for (int x = t; x < N - t; x++) { Set(x, t, dr, dg, db); Set(x, N - 1 - t, dr, dg, db); Set(t, x, dr, dg, db); Set(N - 1 - t, x, dr, dg, db); }

        // draw the label centered, scaled up from the 8x8 font
        int n = label.Length;
        int maxW = 190, maxH = 150;
        int scale = Math.Min(maxW / (n * 8), maxH / 8);
        if (scale < 1) scale = 1;
        int glyphW = 8 * scale, gap = scale;             // 1 cell gap between glyphs
        int totalW = n * glyphW + (n - 1) * gap;
        int ox = (N - totalW) / 2, oy = (N - 8 * scale) / 2;
        for (int ci = 0; ci < n; ci++)
        {
            byte[] g = Glyph(label[ci]);
            int gx = ox + ci * (glyphW + gap);
            for (int row = 0; row < 8; row++)
                for (int col = 0; col < 8; col++)
                    if ((g[row] & (0x80 >> col)) != 0)
                        for (int sy = 0; sy < scale; sy++)
                            for (int sx = 0; sx < scale; sx++)
                                Set(gx + col * scale + sx, oy + row * scale + sy, fg.r, fg.g, fg.b);
        }
        return px;
    }

    // ---- minimal 8x8 font (bit 7 = leftmost), only the glyphs the labels use ----
    static byte[] Glyph(char c) => c switch
    {
        'A' => new byte[] { 0b00111000, 0b01101100, 0b11000110, 0b11000110, 0b11111110, 0b11000110, 0b11000110, 0 },
        'B' => new byte[] { 0b11111100, 0b01100110, 0b01100110, 0b01111100, 0b01100110, 0b01100110, 0b11111100, 0 },
        'C' => new byte[] { 0b00111100, 0b01100110, 0b11000000, 0b11000000, 0b11000000, 0b01100110, 0b00111100, 0 },
        'F' => new byte[] { 0b11111110, 0b01100000, 0b01100000, 0b01111100, 0b01100000, 0b01100000, 0b11110000, 0 },
        'G' => new byte[] { 0b00111100, 0b01100110, 0b11000000, 0b11001110, 0b11000110, 0b01100110, 0b00111110, 0 },
        'H' => new byte[] { 0b11000110, 0b11000110, 0b11000110, 0b11111110, 0b11000110, 0b11000110, 0b11000110, 0 },
        'I' => new byte[] { 0b00111100, 0b00011000, 0b00011000, 0b00011000, 0b00011000, 0b00011000, 0b00111100, 0 },
        'K' => new byte[] { 0b11000110, 0b11001100, 0b11011000, 0b11110000, 0b11011000, 0b11001100, 0b11000110, 0 },
        'L' => new byte[] { 0b11110000, 0b01100000, 0b01100000, 0b01100000, 0b01100000, 0b01100110, 0b11111110, 0 },
        'M' => new byte[] { 0b11000110, 0b11101110, 0b11111110, 0b11010110, 0b11000110, 0b11000110, 0b11000110, 0 },
        'P' => new byte[] { 0b11111100, 0b01100110, 0b01100110, 0b01111100, 0b01100000, 0b01100000, 0b11110000, 0 },
        'Q' => new byte[] { 0b01111100, 0b11000110, 0b11000110, 0b11000110, 0b11011110, 0b01111100, 0b00001110, 0 },
        'S' => new byte[] { 0b00111110, 0b01100000, 0b01100000, 0b00111100, 0b00000110, 0b00000110, 0b01111100, 0 },
        'T' => new byte[] { 0b11111111, 0b00011000, 0b00011000, 0b00011000, 0b00011000, 0b00011000, 0b00011000, 0 },
        'U' => new byte[] { 0b11000110, 0b11000110, 0b11000110, 0b11000110, 0b11000110, 0b11000110, 0b01111100, 0 },
        '2' => new byte[] { 0b01111100, 0b11000110, 0b00000110, 0b00011100, 0b00110000, 0b01100000, 0b11111110, 0 },
        '+' => new byte[] { 0b00000000, 0b00011000, 0b00011000, 0b01111110, 0b00011000, 0b00011000, 0b00000000, 0 },
        _   => new byte[8],
    };

    // ---- minimal PNG encoder (truecolor + alpha, no filtering) ----
    static byte[] EncodePng(int w, int h, byte[] rgba)
    {
        using var ms = new MemoryStream();
        ms.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        var ihdr = new byte[13];
        WriteBE(ihdr, 0, w); WriteBE(ihdr, 4, h);
        ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;   // 8-bit RGBA
        Chunk(ms, "IHDR", ihdr);

        var raw = new byte[h * (1 + w * 4)];
        for (int y = 0; y < h; y++)
        {
            raw[y * (1 + w * 4)] = 0;                                          // filter: none
            Array.Copy(rgba, y * w * 4, raw, y * (1 + w * 4) + 1, w * 4);
        }
        byte[] idat;
        using (var cm = new MemoryStream())
        {
            using (var z = new ZLibStream(cm, CompressionLevel.Optimal, true)) z.Write(raw, 0, raw.Length);
            idat = cm.ToArray();
        }
        Chunk(ms, "IDAT", idat);
        Chunk(ms, "IEND", Array.Empty<byte>());
        return ms.ToArray();
    }

    static void WriteBE(byte[] b, int o, int v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }
    static void Chunk(Stream s, string type, byte[] data)
    {
        var len = new byte[4]; WriteBE(len, 0, data.Length); s.Write(len);
        var t = Encoding.ASCII.GetBytes(type); s.Write(t); s.Write(data);
        uint crc = Crc32(t, data); var c = new byte[4]; WriteBE(c, 0, (int)crc); s.Write(c);
    }
    static readonly uint[] CrcTable = BuildCrc();
    static uint[] BuildCrc()
    {
        var t = new uint[256];
        for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; t[i] = c; }
        return t;
    }
    static uint Crc32(byte[] a, byte[] b)
    {
        uint c = 0xFFFFFFFF;
        foreach (var x in a) c = CrcTable[(c ^ x) & 0xFF] ^ (c >> 8);
        foreach (var x in b) c = CrcTable[(c ^ x) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFF;
    }
}
