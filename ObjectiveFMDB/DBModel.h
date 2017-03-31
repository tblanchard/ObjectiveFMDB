//
//  DBModel.h
//
//  Created by Todd Blanchard on 1/27/16.
//

#import <Foundation/Foundation.h>

#import "FMDatabaseQueue+ObjectiveFMDB.h"

@interface DBModel : NSObject

// DBModel uses FMDatabaseQueue to serialize access
// and make it easy to do database stuff from background
// threads.

// Assumed primary key column - you can change this by overriding primaryKeyPropertyNames
@property (nonatomic, assign) NSInteger id;

// Must be called first - typically with username
+(void)setDatabaseName:(NSString*)name;

+(void)closeDatabase;

+(FMDatabaseQueue*)queue;
// return the database to use for this instance
-(FMDatabaseQueue*)queue;

// Objective C Introspection
+(NSDictionary*)columnDefinitionsFromProperties;
+(NSArray*) primaryKeyPropertyNames;

// SQLite Introspection
+(void)createTableInDatabase:(FMDatabase*)db;
+(void)createTable;

+(void)dropTableInDatabase:(FMDatabase*)db;
+(void)dropTable;

+(NSString*)tablename;

+(NSArray*)columnsInDatabase:(FMDatabase*)db;
+(NSArray*)columns;

+(NSArray*)columnNames;

+(NSArray*)primaryKeyColumns;
+(NSArray*)primaryKeyColumnsInDatabase:(FMDatabase*)db;

+(NSArray*)primaryKeyColumnNames;
+(NSArray*)primaryKeyColumnNamesInDatabase:(FMDatabase*)db;

+(NSUInteger)countInDatabase:(FMDatabase*)db;
+(NSUInteger)count;

+(NSUInteger)countWhere:(NSDictionary*)where inDatabase:(FMDatabase*)db;
+(NSUInteger)countWhere:(NSDictionary*)where;

+(NSUInteger)countWhereSql:(NSString*)where parameters:(NSArray*)params inDatabase:(FMDatabase*)db;
+(NSUInteger)countWhereSql:(NSString*)where parameters:(NSArray*)params;

// default ordering - only need to define orderByColumns
// the default is @[[@"id",@"ASC"]] which orders by id ascending
+(NSArray*)orderByColumns;
+(NSArray*)reverseOrderByColumns;

// first or last record based on default sort orderings
+(instancetype)firstInDatabase:(FMDatabase*)db;
+(instancetype)first;

+(instancetype)lastInDatabase:(FMDatabase*)db;
+(instancetype)last;

+(NSArray*)allInDatabase:(FMDatabase*)db;
+(NSArray*)all;

+(id)find:(id)key inDatabase:(FMDatabase*)db;
+(id)find:(id)key;

+(id)find:(id)key orderBy:(NSArray*)orderings inDatabase:(FMDatabase*)db;
+(id)find:(id)key orderBy:(NSArray*)orderings;

+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit inDatabase:(FMDatabase*)db;
+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit;

+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit offset:(NSInteger)offset inDatabase:(FMDatabase*)db;
+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit offset:(NSInteger)offset;

+(id)find:(id)key limit:(NSInteger)limit inDatabase:(FMDatabase*)db;
+(id)find:(id)key limit:(NSInteger)limit;

+(NSArray*)findAll:(id)key inDatabase:(FMDatabase*)db;
+(NSArray*)findAll:(id)key;

+(NSArray*)findAll:(id)key limit:(NSInteger)limit inDatabase:(FMDatabase*)db;
+(NSArray*)findAll:(id)key limit:(NSInteger)limit;

+(NSArray*)findBySql:(NSString*)sql parameters:(NSArray*)params inDatabase:(FMDatabase*)db;
+(NSArray*)findBySql:(NSString*)sql parameters:(NSArray*)params;

+(NSArray*)findBySqlWhere:(NSString*)sql parameters:(NSArray*)params inDatabase:(FMDatabase*)db;
+(NSArray*)findBySqlWhere:(NSString*)sql parameters:(NSArray*)params;

+(void)remove:(id)key inDatabase:(FMDatabase*)db;
+(void)remove:(id)key;

+(NSArray*)placeholders:(NSInteger)count;
+(NSString*)placeholderString:(NSInteger)count;

-(NSDictionary*)primaryKeyValues;
-(NSDictionary*)databaseColumnValues;
-(NSDictionary*)serverColumnValues;

//companion to dictionaryWithValuesForKeys: -tb
-(NSArray*)arrayWithValuesForKeys:(NSArray*)keys;

-(BOOL)saveInDatabase:(FMDatabase*)db;
-(BOOL)save;

-(void)removeInDatabase:(FMDatabase*)db;
-(void)remove;

-(void)refreshInDatabase:(FMDatabase*)db;
-(void)refresh;

-(NSURL*)cacheLocationForMediaURL:(NSURL*)url;
-(BOOL)mediaURLIsCached:(NSURL*)url;

// Paging support
-(NSArray*)nextObjects:(NSInteger)limit;
-(NSArray*)previousObjects:(NSInteger)limit;

// mapping from json - transient
+(NSArray*)fromJsonArray:(NSArray*)items;
+(instancetype)fromJsonDictionary:(NSDictionary*)items;

// mapping from json - persistent
+(NSArray*)fromJsonArray:(NSArray*)items inDatabase:(FMDatabase*)db;
+(instancetype)fromJsonDictionary:(NSDictionary*)items inDatabase:(FMDatabase*)db;


@end
