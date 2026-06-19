/* xeyes — the classic X11 demo, written in our C, compiled to .NET IL.
 * Two eyes whose pupils track the mouse pointer. Uses the CRuntime graphics
 * hooks (gfx_*) which a host (ilgfx, an Avalonia window) blits to screen. */

int main(void)
{
    int W = 420, H = 260;
    gfx_open(W, H, (int)"xeyes");

    int ex[2]; int ey[2];
    ex[0] = 115; ey[0] = 130;            /* left eye  centre */
    ex[1] = 305; ey[1] = 130;            /* right eye centre */
    int rx = 88, ry = 112;               /* sclera (white) radii */
    int pr = 24;                         /* pupil radius */
    int wall = 7;                        /* keep the pupil this far inside the rim */

    int bg = 0xB8C0C8;                   /* window background (slate grey) */
    int white = 0xFFFFFF, black = 0x101010;

    while (!gfx_poll())
    {
        int mx = gfx_mousex();
        int my = gfx_mousey();

        gfx_clear(bg);

        int i;
        for (i = 0; i < 2; i++)
        {
            gfx_fill_ellipse(ex[i], ey[i], rx, ry, white);     /* eyeball  */
            gfx_draw_ellipse(ex[i], ey[i], rx, ry, black);     /* rim      */

            /* place the pupil: sit at the mouse if it is inside the inner
             * ellipse, otherwise clamp to the rim along that direction. */
            double dx = mx - ex[i];
            double dy = my - ey[i];
            double irx = rx - pr - wall;
            double iry = ry - pr - wall;
            double nx = dx / irx;
            double ny = dy / iry;
            double px, py;
            if (nx * nx + ny * ny <= 1.0) { px = mx; py = my; }
            else { double a = atan2(dy, dx); px = ex[i] + irx * cos(a); py = ey[i] + iry * sin(a); }

            gfx_fill_ellipse((int)px, (int)py, pr, pr, black); /* pupil */
        }

        gfx_present();
        gfx_sleep(16);
    }
    return 0;
}
