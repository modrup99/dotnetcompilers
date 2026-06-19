class Counter {
  int n;
public:
  void reset() { n = 0; }
  void inc() { n = n + 1; }
  int get() { return n; }
};
int main() {
  Counter c;
  c.reset();
  c.inc(); c.inc(); c.inc();
  printf("count = %d\n", c.get());
  return 0;
}
