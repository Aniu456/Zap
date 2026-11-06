#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// macOS 26 raises NSInternalInconsistencyException from -[NSWindow setCollectionBehavior:]
// when a window is both on all Spaces and set to move to the active Space. That exception
// escapes Swift tasks as EXC_BAD_ACCESS. Strip the illegal pair before AppKit validates it,
// and if validation still fails, fall back to all-Spaces alone so the process stays up.

static void (*zap_originalSetCollectionBehavior)(id, SEL, NSUInteger);
static _Thread_local int zap_inSetCollectionBehavior = 0;

static void zap_setCollectionBehavior(id self, SEL cmd, NSUInteger behavior) {
    if (zap_inSetCollectionBehavior) {
        zap_originalSetCollectionBehavior(self, cmd, behavior);
        return;
    }
    if (behavior & NSWindowCollectionBehaviorCanJoinAllSpaces) {
        behavior &= ~NSWindowCollectionBehaviorMoveToActiveSpace;
        behavior &= ~NSWindowCollectionBehaviorFullScreenAuxiliary;
        behavior &= ~NSWindowCollectionBehaviorFullScreenPrimary;
        behavior &= ~NSWindowCollectionBehaviorStationary;
    }
    zap_inSetCollectionBehavior = 1;
    @try {
        zap_originalSetCollectionBehavior(self, cmd, behavior);
    } @catch (NSException *exception) {
        @try {
            zap_originalSetCollectionBehavior(
                self,
                cmd,
                NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorIgnoresCycle
            );
        } @catch (NSException *ignored) {
        }
    } @finally {
        zap_inSetCollectionBehavior = 0;
    }
}

__attribute__((constructor))
static void zap_installWindowSpacesGuard(void) {
    Method method = class_getInstanceMethod([NSWindow class], @selector(setCollectionBehavior:));
    if (method == NULL) {
        return;
    }
    zap_originalSetCollectionBehavior = (void (*)(id, SEL, NSUInteger))method_getImplementation(method);
    method_setImplementation(method, (IMP)zap_setCollectionBehavior);
}
