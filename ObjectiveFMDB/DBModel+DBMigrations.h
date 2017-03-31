//
//  DBModel+DBMigrations.h
//  TruePic
//
//  Created by Todd Blanchard on 1/10/17.
//  Copyright © 2017 Todd Blanchard. All rights reserved.
//

#import "DBModel.h"

@interface DBModel (DBMigrations)

+(void)performNeededMigrationsInDatabase:(FMDatabase*)db;

@end

@protocol DBMigration <NSObject>

+(void)performMigrationInDatabase:(FMDatabase*)db;

@end

@interface DBMigration : NSObject <DBMigration>

+(void)performMigrationInDatabase:(FMDatabase*)db;

@end

@interface DBMigration_0 : DBMigration

+(void)performMigrationInDatabase:(FMDatabase*)db;

@end
