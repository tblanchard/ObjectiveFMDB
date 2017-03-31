//
//  FMDatabase+DistanceFunction.m
//  NumberStation
//
//  Created by Todd Blanchard on 5/5/14.
//
//

#import "FMDatabase+DistanceFunction.h"

#define DEG2RAD(degrees) (degrees / 180.0 * M_PI) // degrees * pi over 180

static void distanceFunc(sqlite3_context *context, int argc, sqlite3_value **argv)
{
    // check that we have four arguments (lat1, lon1, lat2, lon2)
    assert(argc == 4);
    // check that all four arguments are non-null
    if (sqlite3_value_type(argv[0]) == SQLITE_NULL || sqlite3_value_type(argv[1]) == SQLITE_NULL || sqlite3_value_type(argv[2]) == SQLITE_NULL || sqlite3_value_type(argv[3]) == SQLITE_NULL) {
        sqlite3_result_null(context);
        return;
    }
    // get the four argument values
    double lat1 = sqlite3_value_double(argv[0]);
    double lon1 = sqlite3_value_double(argv[1]);
    double lat2 = sqlite3_value_double(argv[2]);
    double lon2 = sqlite3_value_double(argv[3]);
    // convert lat1 and lat2 into radians now, to avoid doing it twice below
    double lat1rad = DEG2RAD(lat1);
    double lat2rad = DEG2RAD(lat2);
    // apply the spherical law of cosines to our latitudes and longitudes, and set the result appropriately
    // 6378.1 is the approximate radius of the earth in kilometres
    double distance = (acos(sin(lat1rad) * sin(lat2rad) + cos(lat1rad) * cos(lat2rad) * cos(DEG2RAD(lon2) - DEG2RAD(lon1))) * 6378.1)*1000;
    
    sqlite3_result_double(context, distance);
}

@implementation FMDatabase (UserFunctions)

-(BOOL)addDistanceFunction
{
    return 0 == sqlite3_create_function(self.sqliteHandle, "distance", 4, SQLITE_UTF8, NULL, &distanceFunc, NULL, NULL);
}

@end
