int add(int a, int b) { return a + b; }
int main() {
  int i;
  for (i = 0; i < 4; i = i + 1) printf("%d ", add(i, i));
  printf("\n");
  return 0;
}
