class Animal {
public:
  int legs;
  Animal() { legs = 4; }
  virtual const char* sound() { return "..."; }
  void describe() { printf("%s has %d legs and says %s\n", kind(), this->legs, sound()); }
  virtual const char* kind() { return "animal"; }
};
class Dog : public Animal {
public:
  virtual const char* sound() { return "woof"; }
  virtual const char* kind() { return "dog"; }
};
class Puppy : public Dog {
public:
  virtual const char* sound() { return "yip"; }
};
int main() {
  Animal a; Dog d; Puppy p;
  a.describe();
  d.describe();
  p.describe();
  Animal* arr[3]; arr[0] = &a; arr[1] = &d; arr[2] = new Puppy();
  int i;
  for (i = 0; i < 3; i = i + 1) printf("  -> %s\n", arr[i]->sound());
  return 0;
}
