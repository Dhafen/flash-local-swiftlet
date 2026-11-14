#include <assert.h>
#include "../touch-zone.h"

int main(void) {
    assert(sp_mobile_zone(0.20, 0.70, 0) == SPMobileMove);
    assert(sp_mobile_zone(0.80, 0.65, 0) == SPMobileLook);
    assert(sp_mobile_zone(0.20, 0.70, 1) == SPMobileInterface);
    assert(sp_mobile_zone(0.80, 0.65, 1) == SPMobileInterface);
    assert(sp_mobile_zone(0.45, 0.65, 0) == SPMobileDefault);
    assert(sp_mobile_zone(-0.01, 0.65, 1) == SPMobileDefault);
}
