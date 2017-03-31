//
//  EGODatabaseResult+ORM.h
//  NumberStation
//
//  Created by Todd Blanchard on 3/20/14.
//
//

#import "FMResultSet.h"

@interface FMResultSet (ObjectiveFMDB)

- (NSArray*)objectsOfClass:(Class)c;
- (NSArray*)objectsOfClass:(Class)c mappings:(NSDictionary*)d;
- (NSArray*)resultDictionaries;

@end
