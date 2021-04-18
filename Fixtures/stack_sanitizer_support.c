__attribute__((__import_module__("__stack_sanitizer"),
               __import_name__("report_stack_overflow")))
void __stack_sanitizer_report_stack_overflow(void);

__attribute__((visibility("hidden")))
void __dummy() {
    __stack_sanitizer_report_stack_overflow();
}
