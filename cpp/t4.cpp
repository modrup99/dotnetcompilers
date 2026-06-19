class Shape {
public:
  virtual int area() { return 0; }
  virtual const char* name() { return "shape"; }
};
class Square : public Shape {
  int s;
public:
  void setside(int x) { s = x; }
  virtual int area() { return s * s; }
  virtual const char* name() { return "square"; }
};
int main() {
  Square sq;
  sq.setside(4);
  Shape* p = &sq;
  printf("%s area=%d\n", p->name(), p->area());
  Shape* h = new Square();
  printf("heap name=%s\n", h->name());
  delete h;
  return 0;
}
