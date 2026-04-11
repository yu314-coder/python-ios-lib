# C++ Interpreter (offlinai_cpp)

> **Type:** Tree-walking C++17 interpreter | **Location:** `gcc/offlinai_cpp.c`, `gcc/offlinai_cpp.h` | **Language:** C++17 subset | **App Store safe**

A self-contained C++17 interpreter that extends the C interpreter with classes, templates, namespaces, STL containers, RAII, and modern C++ features. Lexes, parses, and interprets C++ code at runtime. No JIT, no code generation, no external compiler needed.

---

## Quick Start

```cpp
#include <iostream>
#include <vector>
#include <string>
#include <algorithm>

using namespace std;

class Shape {
public:
    virtual double area() const = 0;
    virtual string name() const = 0;
    virtual ~Shape() {}
};

class Circle : public Shape {
    double radius;
public:
    Circle(double r) : radius(r) {}
    double area() const override { return 3.14159 * radius * radius; }
    string name() const override { return "Circle"; }
};

class Rectangle : public Shape {
    double w, h;
public:
    Rectangle(double w, double h) : w(w), h(h) {}
    double area() const override { return w * h; }
    string name() const override { return "Rectangle"; }
};

int main() {
    vector<Shape*> shapes;
    shapes.push_back(new Circle(5.0));
    shapes.push_back(new Rectangle(3.0, 4.0));

    for (auto s : shapes) {
        cout << s->name() << ": area = " << s->area() << endl;
        delete s;
    }

    // Lambdas
    auto square = [](int x) { return x * x; };
    cout << "5 squared = " << square(5) << endl;

    return 0;
}
```

---

## Supported Data Types

| Type | Description |
|------|-------------|
| `int` | 64-bit integer (all integer types map here) |
| `long` / `long long` | Same as int internally |
| `short` | Parsed, same storage as int |
| `unsigned` | Parsed, treated as signed internally |
| `float` / `double` | 64-bit double precision |
| `char` | Single character, escape sequences |
| `bool` | Boolean (`true` / `false`) |
| `void` | Return type or pointer base |
| `auto` | Type deduction from initializer |
| `std::string` | Dynamic string class |
| `std::vector<T>` | Dynamic array |
| `std::map<K,V>` | Ordered associative container |
| `std::set<T>` | Ordered unique elements |
| `std::pair<A,B>` | Pair of values |
| `T*` | Pointer type (virtual memory backed) |
| `T&` | Reference type (alias semantics) |

---

## Classes & Object-Oriented Programming

### Class Declaration

```cpp
class Point {
private:
    double x, y;

public:
    // Constructor
    Point(double x, double y) : x(x), y(y) {}

    // Default constructor
    Point() : x(0), y(0) {}

    // Copy constructor
    Point(const Point& other) : x(other.x), y(other.y) {}

    // Destructor
    ~Point() {}

    // Member functions
    double getX() const { return x; }
    double getY() const { return y; }
    void setX(double val) { x = val; }
    void setY(double val) { y = val; }

    double distance(const Point& other) const {
        double dx = x - other.x;
        double dy = y - other.y;
        return sqrt(dx*dx + dy*dy);
    }

    // Operator overloading
    Point operator+(const Point& other) const {
        return Point(x + other.x, y + other.y);
    }

    Point operator-(const Point& other) const {
        return Point(x - other.x, y - other.y);
    }

    bool operator==(const Point& other) const {
        return x == other.x && y == other.y;
    }

    // Friend function
    friend ostream& operator<<(ostream& os, const Point& p);
};

ostream& operator<<(ostream& os, const Point& p) {
    os << "(" << p.x << ", " << p.y << ")";
    return os;
}
```

### Inheritance

```cpp
class Animal {
protected:
    string name;
    int age;
public:
    Animal(string name, int age) : name(name), age(age) {}
    virtual void speak() const { cout << name << " makes a sound" << endl; }
    virtual ~Animal() {}
    string getName() const { return name; }
};

class Dog : public Animal {
    string breed;
public:
    Dog(string name, int age, string breed)
        : Animal(name, age), breed(breed) {}

    void speak() const override {
        cout << name << " barks!" << endl;
    }

    string getBreed() const { return breed; }
};

class Cat : public Animal {
public:
    Cat(string name, int age) : Animal(name, age) {}
    void speak() const override {
        cout << name << " meows!" << endl;
    }
};
```

### Access Specifiers

| Specifier | Description |
|-----------|-------------|
| `public` | Accessible from anywhere |
| `private` | Accessible only within the class |
| `protected` | Accessible in class and derived classes |

### Special Member Functions

| Feature | Syntax |
|---------|--------|
| Default constructor | `ClassName()` |
| Parameterized constructor | `ClassName(params)` |
| Copy constructor | `ClassName(const ClassName&)` |
| Destructor | `~ClassName()` |
| Initializer list | `ClassName(int x) : member(x) {}` |
| Virtual functions | `virtual void func()` |
| Pure virtual | `virtual void func() = 0;` |
| Override | `void func() override` |
| Const member | `void func() const` |

---

## The `this` Pointer

```cpp
class Counter {
    int count;
public:
    Counter() : count(0) {}

    Counter& increment() {
        count++;
        return *this;  // Return reference to self (method chaining)
    }

    int getCount() const { return count; }
};

Counter c;
c.increment().increment().increment();
cout << c.getCount() << endl;  // 3
```

---

## Operator Overloading

| Operator | Signature |
|----------|-----------|
| `+` `-` `*` `/` `%` | `T operator+(const T& rhs) const` |
| `==` `!=` `<` `>` `<=` `>=` | `bool operator==(const T& rhs) const` |
| `<<` (stream) | `friend ostream& operator<<(ostream&, const T&)` |
| `>>` (stream) | `friend istream& operator>>(istream&, T&)` |
| `[]` (subscript) | `T& operator[](int index)` |
| `()` (function call) | `T operator()(args)` |
| `++` `--` (prefix) | `T& operator++()` |
| `++` `--` (postfix) | `T operator++(int)` |
| `=` (assignment) | `T& operator=(const T& rhs)` |
| `+=` `-=` `*=` `/=` | `T& operator+=(const T& rhs)` |
| Unary `-` | `T operator-() const` |

---

## Memory Management

```cpp
// Stack allocation
Point p(3.0, 4.0);

// Heap allocation
Point* ptr = new Point(5.0, 6.0);
cout << ptr->getX() << endl;
delete ptr;

// Array allocation
int* arr = new int[10];
for (int i = 0; i < 10; i++) arr[i] = i * i;
delete[] arr;
```

| Operator | Description |
|----------|-------------|
| `new T(args)` | Allocate single object on heap, call constructor |
| `new T[n]` | Allocate array of n objects |
| `delete ptr` | Destroy object and free memory |
| `delete[] arr` | Destroy array and free memory |

---

## References

```cpp
int x = 42;
int& ref = x;     // ref is an alias for x
ref = 100;
cout << x << endl;  // 100

// Pass by reference
void swap(int& a, int& b) {
    int temp = a;
    a = b;
    b = temp;
}

// Const reference
void print(const string& s) {
    cout << s << endl;
}
```

---

## Namespaces

```cpp
namespace Math {
    constexpr double PI = 3.14159265358979;
    double circleArea(double r) { return PI * r * r; }
    double circumference(double r) { return 2 * PI * r; }
}

namespace Physics {
    constexpr double G = 9.81;
    double fallTime(double height) { return sqrt(2 * height / G); }
}

int main() {
    cout << Math::circleArea(5.0) << endl;
    cout << Physics::fallTime(100.0) << endl;

    using namespace Math;
    cout << circleArea(10.0) << endl;

    return 0;
}
```

---

## Standard Library (STL)

### `std::string`

| Method | Description |
|--------|-------------|
| `string s = "hello"` | Construction |
| `s.length()` / `s.size()` | String length |
| `s.empty()` | Check if empty |
| `s.substr(pos, len)` | Substring |
| `s.find(str)` | Find substring (returns `string::npos` if not found) |
| `s.rfind(str)` | Reverse find |
| `s.replace(pos, len, str)` | Replace substring |
| `s.append(str)` / `s += str` | Append |
| `s.insert(pos, str)` | Insert at position |
| `s.erase(pos, len)` | Erase characters |
| `s.c_str()` | C-string pointer |
| `s[i]` / `s.at(i)` | Character access |
| `s.front()` / `s.back()` | First/last character |
| `s.push_back(c)` | Append character |
| `s.pop_back()` | Remove last character |
| `s.compare(str)` | Compare strings |
| `to_string(n)` | Convert number to string |
| `stoi(s)` / `stod(s)` | Convert string to int/double |

### `std::vector<T>`

| Method | Description |
|--------|-------------|
| `vector<int> v` | Default construction |
| `vector<int> v(n, val)` | N elements with value |
| `vector<int> v = {1,2,3}` | Initializer list |
| `v.push_back(x)` | Add element to end |
| `v.pop_back()` | Remove last element |
| `v.size()` | Number of elements |
| `v.empty()` | Check if empty |
| `v[i]` / `v.at(i)` | Element access |
| `v.front()` / `v.back()` | First/last element |
| `v.begin()` / `v.end()` | Iterator range |
| `v.insert(it, val)` | Insert at iterator position |
| `v.erase(it)` | Erase at iterator position |
| `v.clear()` | Remove all elements |
| `v.resize(n)` | Resize container |
| `v.reserve(n)` | Reserve capacity |
| `v.capacity()` | Current capacity |

### `std::map<K, V>`

| Method | Description |
|--------|-------------|
| `map<string, int> m` | Default construction |
| `m[key] = value` | Insert or update |
| `m.at(key)` | Access with bounds check |
| `m.find(key)` | Find element (returns iterator) |
| `m.count(key)` | Check existence (0 or 1) |
| `m.erase(key)` | Remove by key |
| `m.size()` | Number of elements |
| `m.empty()` | Check if empty |
| `m.begin()` / `m.end()` | Iterator range |
| `m.insert({key, value})` | Insert pair |
| `m.clear()` | Remove all |

### `std::pair<A, B>`

```cpp
pair<string, int> p = {"hello", 42};
cout << p.first << " " << p.second << endl;

auto p2 = make_pair(3.14, "pi");
```

### `std::set<T>`

| Method | Description |
|--------|-------------|
| `set<int> s` | Default construction |
| `s.insert(x)` | Insert element |
| `s.erase(x)` | Remove element |
| `s.count(x)` | Check existence (0 or 1) |
| `s.find(x)` | Find element (iterator) |
| `s.size()` | Number of elements |
| `s.empty()` | Check if empty |
| `s.begin()` / `s.end()` | Iterator range |
| `s.clear()` | Remove all |

---

## STL Algorithms (`<algorithm>`)

| Function | Description |
|----------|-------------|
| `sort(begin, end)` | Sort range in ascending order |
| `sort(begin, end, comp)` | Sort with custom comparator |
| `reverse(begin, end)` | Reverse range |
| `find(begin, end, value)` | Find first occurrence |
| `count(begin, end, value)` | Count occurrences |
| `min_element(begin, end)` | Iterator to minimum |
| `max_element(begin, end)` | Iterator to maximum |
| `accumulate(begin, end, init)` | Sum elements (from `<numeric>`) |
| `binary_search(begin, end, value)` | Binary search (sorted range) |
| `lower_bound(begin, end, value)` | First element >= value |
| `upper_bound(begin, end, value)` | First element > value |
| `unique(begin, end)` | Remove consecutive duplicates |
| `fill(begin, end, value)` | Fill range with value |
| `copy(begin, end, dest)` | Copy range |
| `swap(a, b)` | Swap two values |
| `next_permutation(begin, end)` | Next lexicographic permutation |
| `for_each(begin, end, func)` | Apply function to each element |
| `transform(begin, end, dest, func)` | Transform each element |
| `remove_if(begin, end, pred)` | Remove elements matching predicate |

---

## I/O Streams

### `std::cout` / `std::cin`

```cpp
#include <iostream>
using namespace std;

// Output
cout << "Hello, " << "World!" << endl;
cout << "x = " << 42 << ", pi = " << 3.14 << endl;

// Input (returns default values on iOS -- no stdin)
int n;
cin >> n;  // n = 0 (no stdin on iOS)

string line;
getline(cin, line);  // line = "" (no stdin)
```

### I/O Manipulators

| Manipulator | Description |
|-------------|-------------|
| `endl` | Newline + flush |
| `setw(n)` | Set field width |
| `setprecision(n)` | Set decimal precision |
| `fixed` | Fixed-point notation |
| `scientific` | Scientific notation |
| `left` / `right` | Alignment |
| `setfill(c)` | Fill character |
| `hex` / `oct` / `dec` | Integer base |
| `boolalpha` | Print bool as "true"/"false" |
| `showpoint` | Always show decimal point |

---

## Modern C++ Features

### `auto` Type Deduction

```cpp
auto x = 42;          // int
auto pi = 3.14;       // double
auto s = string("hi"); // string
auto v = vector<int>{1, 2, 3};  // vector<int>
```

### Range-Based For Loop

```cpp
vector<int> nums = {1, 2, 3, 4, 5};
for (auto n : nums) {
    cout << n << " ";
}

for (auto& n : nums) {  // By reference (modifiable)
    n *= 2;
}

map<string, int> m = {{"a", 1}, {"b", 2}};
for (auto& [key, value] : m) {  // Structured bindings (C++17)
    cout << key << "=" << value << endl;
}
```

### Lambda Expressions

```cpp
// Basic lambda
auto add = [](int a, int b) { return a + b; };
cout << add(3, 4) << endl;  // 7

// Capture by value
int multiplier = 3;
auto mul = [multiplier](int x) { return x * multiplier; };
cout << mul(5) << endl;  // 15

// Capture by reference
int total = 0;
auto accumulate = [&total](int x) { total += x; };
accumulate(10);
accumulate(20);
cout << total << endl;  // 30

// Capture all by value [=] or reference [&]
auto f = [=]() { return multiplier * 2; };
auto g = [&]() { total += 100; };

// Lambda as sort comparator
vector<int> v = {5, 2, 8, 1, 9};
sort(v.begin(), v.end(), [](int a, int b) { return a > b; });
// v = {9, 8, 5, 2, 1}
```

### Templates

```cpp
// Function template
template<typename T>
T maximum(T a, T b) {
    return (a > b) ? a : b;
}

cout << maximum(3, 7) << endl;       // 7
cout << maximum(3.14, 2.71) << endl; // 3.14

// Class template
template<typename T>
class Stack {
    vector<T> data;
public:
    void push(T val) { data.push_back(val); }
    T pop() {
        T val = data.back();
        data.pop_back();
        return val;
    }
    bool empty() const { return data.empty(); }
    int size() const { return data.size(); }
};

Stack<int> intStack;
intStack.push(1);
intStack.push(2);
cout << intStack.pop() << endl;  // 2

Stack<string> strStack;
strStack.push("hello");
```

### Exception Handling

```cpp
#include <stdexcept>

try {
    int x = 10, y = 0;
    if (y == 0) throw runtime_error("Division by zero!");
    cout << x / y << endl;
} catch (const runtime_error& e) {
    cout << "Error: " << e.what() << endl;
} catch (...) {
    cout << "Unknown error" << endl;
}

// Custom exception
class MyError : public exception {
    string msg;
public:
    MyError(string m) : msg(m) {}
    const char* what() const noexcept override { return msg.c_str(); }
};
```

---

## Supported C Features (inherited from C interpreter)

All C89/C99/C23 features from the C interpreter are available:

- All C operators (48), control flow, functions, pointers, arrays (1D/2D)
- Structs, unions, enums, typedef
- Preprocessor (`#define`, `#ifdef`, `#ifndef`, `#if`, `#else`, `#elif`, `#endif`, `#undef`, `#warning`)
- Function pointers, static variables, goto/labels
- `printf`/`sprintf`/`snprintf`, `<math.h>`, `<string.h>`, `<ctype.h>` functions
- `malloc`/`calloc`/`realloc`/`free`
- C23: `_Static_assert`, `_Generic`, `typeof`, `auto`, `constexpr`, binary literals, digit separators, `[[attributes]]`

---

## Built-in Functions (C++ additions)

| Function | Description |
|----------|-------------|
| `cout << ...` | Standard output stream |
| `cin >> ...` | Standard input (returns defaults on iOS) |
| `endl` | Line ending + flush |
| `to_string(n)` | Number to string conversion |
| `stoi(s)` / `stol(s)` | String to integer |
| `stof(s)` / `stod(s)` | String to float/double |
| `getline(cin, str)` | Read full line |
| `min(a, b)` / `max(a, b)` | Min/max (from `<algorithm>`) |
| `abs(x)` | Absolute value |
| `swap(a, b)` | Swap values |
| `sizeof(T)` | Size of type |
| `static_cast<T>(x)` | Static type cast |

---

## Limits

Same as C interpreter limits plus:

| Limit | Value |
|-------|-------|
| Max classes | 64 |
| Max class members | 64 |
| Max template instantiations | 128 |
| Max inheritance depth | 8 |
| Max namespace depth | 8 |
| Max lambda captures | 32 |
| Max vector elements | 10,000 |
| Max map entries | 4,096 |
| Max string length | 4,096 chars |

---

## Not Supported

| Feature | Notes |
|---------|-------|
| Multiple inheritance | Single inheritance only |
| `std::shared_ptr` / `std::unique_ptr` | Smart pointers not implemented |
| `std::unordered_map` / `std::unordered_set` | Hash containers not implemented |
| `std::tuple` | Use `std::pair` or structs instead |
| `std::optional` / `std::variant` / `std::any` | C++17 vocabulary types not implemented |
| `std::thread` / `std::mutex` | Threading not applicable on iOS interpreter |
| `std::filesystem` | No filesystem access |
| `std::regex` | Regular expressions not implemented |
| Move semantics (`std::move`, `&&`) | Rvalue references not implemented |
| `consteval` / `constinit` | C++20 features not supported |
| Concepts (C++20) | Not implemented |
| Modules (C++20) | Not implemented |
| Coroutines (C++20) | Not implemented |
| `std::array` | Use C arrays or `std::vector` |
| Template specialization | Partial/full specialization not supported |
| Operator `new`/`delete` overloading | Uses built-in allocator |
| `virtual` multiple dispatch | Single dispatch only |
| RTTI (`dynamic_cast`, `typeid`) | Not implemented |
