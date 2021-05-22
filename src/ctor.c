int main(void);
__attribute__((constructor)) static void ctor() {
    main();
}
