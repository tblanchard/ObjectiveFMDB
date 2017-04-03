//
//  DBModel+DBMigrations.m
//
//  Created by Todd Blanchard on 1/10/17.
//  Copyright © 2017 Todd Blanchard. All rights reserved.
//

#import "DBModel+DBMigrations.h"
#import "FMDatabase+ObjectiveFMDB.h"

@interface DBDatabaseMigrationLevel : DBModel

@property (nonatomic, assign) NSUInteger level;

@end

@implementation DBDatabaseMigrationLevel

@end

@implementation DBMigration

+(void)performMigrationInDatabase:(FMDatabase*)db
{
}

@end


@implementation DBMigration_0

+(void)performMigrationInDatabase:(FMDatabase*)db
{
    [DBDatabaseMigrationLevel createTableInDatabase:db];
    DBDatabaseMigrationLevel* level = [DBDatabaseMigrationLevel new];
    level.id = 1;
    level.level = 0;
    [level saveInDatabase:db];
}

@end

@implementation DBModel (DBMigrations)

+(void)performNeededMigrationsInDatabase:(FMDatabase*)db
{
    if(![db tableExists:[DBDatabaseMigrationLevel tablename]])
    {
        [DBMigration_0 performMigrationInDatabase:db];
    }
    
    DBDatabaseMigrationLevel* level = [DBDatabaseMigrationLevel find:@1 inDatabase:db];
    Class migration = nil;
    do
    {
        NSString* migrationClassName = [NSString stringWithFormat:@"DBMigration_%lu",(unsigned long)level.level+1];
        migration = NSClassFromString(migrationClassName);
        if(migration)
        {
            [migration performMigrationInDatabase:db];
            level.level += 1;
            [level saveInDatabase:db];
        }
    } while(migration);
}

@end
