void swap(int& a, int& b) { int t = a; a = b; b = t; }
class Box {
  int v;
public:
  Box(int x) { v = x; }
  int val() { return v; }
  void set(int x) { v = x; }
};
int main() {
  int x = 1, y = 2;
  swap(x, y);
  printf("x=%d y=%d\n", x, y);
  Box* b = new Box(7);
  b->set(b->val() + 3);
  printf("box=%d\n", b->val());
  delete b;
  return 0;
}
