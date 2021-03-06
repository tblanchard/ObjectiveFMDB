//
//  FMDatabase+ObjectiveFMDB.m
//
//  Created by Todd Blanchard on 3/20/14.
//  Copyright © 2017 Todd Blanchard. All rights reserved.
//

#import "FMDatabase+ObjectiveFMDB.h"
#import "FMResultSet+ObjectiveFMDB.h"

@implementation FMDatabase (ObjectiveFMDB)

- (NSArray*)tablenames
{
    return [[NSSet setWithArray:[[self getSchema]valueForKeyPath:@"tbl_name"]]allObjects];
}

- (BOOL)tableExists:(NSString*)tableName {
    
    tableName = [tableName lowercaseString];
    
    FMResultSet *rs = [self executeQuery:@"select [sql] from sqlite_master where [type] = 'table' and lower(name) = ?", tableName,nil];
    
    return [[rs resultDictionaries]count] > 0;
}

/*
 get table with list of tables: result colums: type[STRING], name[STRING],tbl_name[STRING],rootpage[INTEGER],sql[STRING]
 check if table exist in database  (patch from OZLB)
 */
- (NSArray*)getSchema
{
    //result colums: type[STRING], name[STRING],tbl_name[STRING],rootpage[INTEGER],sql[STRING]
    FMResultSet *rs = [self executeQuery:@"SELECT type, name, tbl_name, rootpage, sql FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%' ORDER BY tbl_name, type DESC, name"];
 
    return [rs resultDictionaries];
}

/*
 get table schema: result colums: cid[INTEGER], name,type [STRING], notnull[INTEGER], dflt_value[],pk[INTEGER]
 */
- (NSArray*)getTableSchema:(NSString*)tableName {
    
    //result colums: cid[INTEGER], name,type [STRING], notnull[INTEGER], dflt_value[],pk[INTEGER]
    FMResultSet* rs = [self executeQuery:[NSString stringWithFormat:@"pragma table_info('%@')", tableName]];
    return [rs resultDictionaries];
}

- (BOOL)columnExists:(NSString*)columnName inTableWithName:(NSString*)tableName
{
    tableName  = [tableName lowercaseString];
    columnName = [columnName lowercaseString];
    
    NSArray *rs = [self getTableSchema:tableName];
    
    //check if column is present in table schema
    for(NSDictionary* row in rs)
    {
        if([[row[@"name"] lowercaseString] isEqualToString:columnName])
        {
            return YES;
        }
    }
    return NO;
}

-(NSDictionary*)createScripts
{
    FMResultSet* rs = [self executeQuery:@"select name, sql from sqlite_master where type='table' ORDER BY name"];
    NSArray* rows = [rs resultDictionaries];
    return [NSDictionary dictionaryWithObjects:[rows valueForKey:@"sql"] forKeys:[rows valueForKey:@"name"]];
}

@end
