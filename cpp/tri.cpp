int main() {
    int r = 1;
    while (r <= 4) {
        int c = 0;
        while (c < r) { printf("*"); c = c + 1; }
        printf("\n");
        r = r + 1;
    }
    return 0;
}
