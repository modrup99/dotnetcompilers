using System.Runtime.InteropServices;

namespace Cc;

// Embeds an icon into a native PE (the apphost .exe cc stamps), by writing RT_ICON +
// RT_GROUP_ICON Win32 resources. Accepts .png (embedded as a PNG-format icon entry,
// which Windows Vista+ supports), .ico (entries copied through), and .bmp (converted to
// a DIB icon entry). Windows-only; a failure is non-fatal (the exe still runs).
internal static class IconEmbedder
{
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr BeginUpdateResourceW(string fileName, bool deleteExisting);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool UpdateResourceW(IntPtr h, IntPtr type, IntPtr name, ushort lang, byte[] data, uint cb);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool EndUpdateResourceW(IntPtr h, bool discard);

    const int RT_ICON = 3, RT_GROUP_ICON = 14;
    const ushort LANG = 0x0409;

    sealed class IconImage
    {
        public byte Width, Height, Colors, Reserved;
        public ushort Planes, BitCount;
        public byte[] Data = Array.Empty<byte>();
    }

    public static bool TryEmbed(string exePath, string iconPath, out string error)
    {
        error = "";
        try
        {
            if (!OperatingSystem.IsWindows()) { error = "icons are only embedded on Windows"; return false; }
            if (!File.Exists(iconPath)) { error = $"icon not found: {iconPath}"; return false; }
            var imgs = LoadImages(iconPath);
            if (imgs.Count == 0) { error = "no icon images decoded"; return false; }

            IntPtr h = BeginUpdateResourceW(exePath, false);
            if (h == IntPtr.Zero) { error = "BeginUpdateResource failed"; return false; }
            for (int i = 0; i < imgs.Count; i++)
                if (!UpdateResourceW(h, (IntPtr)RT_ICON, (IntPtr)(i + 1), LANG, imgs[i].Data, (uint)imgs[i].Data.Length))
                { EndUpdateResourceW(h, true); error = "UpdateResource(RT_ICON) failed"; return false; }
            byte[] grp = BuildGroup(imgs);
            if (!UpdateResourceW(h, (IntPtr)RT_GROUP_ICON, (IntPtr)1, LANG, grp, (uint)grp.Length))
            { EndUpdateResourceW(h, true); error = "UpdateResource(RT_GROUP_ICON) failed"; return false; }
            if (!EndUpdateResourceW(h, false)) { error = "EndUpdateResource failed"; return false; }
            return true;
        }
        catch (Exception ex) { error = ex.Message; return false; }
    }

    static List<IconImage> LoadImages(string path)
    {
        byte[] b = File.ReadAllBytes(path);
        // dispatch on content signature, falling back to extension
        if (b.Length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return new() { FromPng(b) };
        if (b.Length > 6 && b[0] == 0 && b[1] == 0 && b[2] == 1 && b[3] == 0) return FromIco(b);
        if (b.Length > 2 && b[0] == (byte)'B' && b[1] == (byte)'M') return new() { FromBmp(b) };
        throw new CCompileException($"unsupported icon format: {path} (use .png, .ico, or .bmp)");
    }

    static IconImage FromPng(byte[] png)
    {
        // IHDR width/height are big-endian at offsets 16/20
        int w = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
        int h = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
        return new IconImage
        {
            Width = (byte)(w >= 256 ? 0 : w),
            Height = (byte)(h >= 256 ? 0 : h),
            Colors = 0, Planes = 1, BitCount = 32, Data = png
        };
    }

    static List<IconImage> FromIco(byte[] ico)
    {
        var list = new List<IconImage>();
        int count = ico[4] | (ico[5] << 8);
        for (int i = 0; i < count; i++)
        {
            int e = 6 + i * 16;
            int bytes = ReadI32(ico, e + 8);
            int off = ReadI32(ico, e + 12);
            var data = new byte[bytes];
            Array.Copy(ico, off, data, 0, bytes);
            list.Add(new IconImage
            {
                Width = ico[e], Height = ico[e + 1], Colors = ico[e + 2], Reserved = ico[e + 3],
                Planes = (ushort)(ico[e + 4] | (ico[e + 5] << 8)),
                BitCount = (ushort)(ico[e + 6] | (ico[e + 7] << 8)),
                Data = data
            });
        }
        return list;
    }

    // Convert a 24/32-bit BMP into a DIB icon entry (doubled height for the AND mask).
    static IconImage FromBmp(byte[] bmp)
    {
        int pixOff = ReadI32(bmp, 10);
        int hdr = ReadI32(bmp, 14);                 // BITMAPINFOHEADER size (40)
        int w = ReadI32(bmp, 18), h = ReadI32(bmp, 22);
        int bpp = bmp[28] | (bmp[29] << 8);
        int rowXor = ((w * bpp + 31) / 32) * 4;
        int rowAnd = ((w + 31) / 32) * 4;
        int xorSize = rowXor * h, andSize = rowAnd * h;
        var dib = new byte[hdr + xorSize + andSize];
        Array.Copy(bmp, 14, dib, 0, hdr);           // copy the info header
        WriteI32(dib, 8, h * 2);                    // biHeight = 2*h (XOR + AND)
        WriteI32(dib, 20, xorSize + andSize);       // biSizeImage
        Array.Copy(bmp, pixOff, dib, hdr, Math.Min(xorSize, bmp.Length - pixOff));   // XOR pixels
        // AND mask left as zeros => fully opaque
        return new IconImage
        {
            Width = (byte)(w >= 256 ? 0 : w), Height = (byte)(h >= 256 ? 0 : h),
            Colors = 0, Planes = 1, BitCount = (ushort)bpp, Data = dib
        };
    }

    static byte[] BuildGroup(List<IconImage> imgs)
    {
        var g = new byte[6 + imgs.Count * 14];
        g[2] = 1; g[4] = (byte)imgs.Count; g[5] = (byte)(imgs.Count >> 8);     // type=1, count
        for (int i = 0; i < imgs.Count; i++)
        {
            int e = 6 + i * 14; var im = imgs[i];
            g[e] = im.Width; g[e + 1] = im.Height; g[e + 2] = im.Colors; g[e + 3] = 0;
            g[e + 4] = (byte)im.Planes; g[e + 5] = (byte)(im.Planes >> 8);
            g[e + 6] = (byte)im.BitCount; g[e + 7] = (byte)(im.BitCount >> 8);
            WriteI32(g, e + 8, im.Data.Length);                                // bytes in resource
            g[e + 12] = (byte)(i + 1); g[e + 13] = (byte)((i + 1) >> 8);        // RT_ICON resource id
        }
        return g;
    }

    static int ReadI32(byte[] b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
    static void WriteI32(byte[] b, int o, int v) { b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); b[o + 2] = (byte)(v >> 16); b[o + 3] = (byte)(v >> 24); }
}
