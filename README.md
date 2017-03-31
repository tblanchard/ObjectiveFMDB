# ObjectiveFMDB

FWIW, I have given up on CocoaPods.  This is a framework.  You can grab it.  It depends on two other frameworks.  The very excellent [FMDB](https://github.com/ccgus/fmdb) and it uses the [SmalltalkCollections](https://github.com/tblanchard/SmalltalkCollections4ObjC)

## What's it?

If you are familiar with ActiveRecord from Rails or CoreData concepts, this should make sense to you.  I use this instead of CoreData because it has less overhead and is quicker.  Yes, you can use this with Swift.  You can create Swift subclasses of DBModel.  You can't write DBModel in Swift, but you can use it.

## OMG ORM!

Yeah, I should have called it that.  Too late. 

Fundamentally, every ORM (Object Relational Mapper) needs a meta model that specifies the model at a relatively abstract level and from the meta model you can then derive various concrete implementations of that model.  Meta models don't get enough attention today.

The CoreData schema editor?  That's a meta model you are editing.  It describes your schema and then in a completely opaque way it hides from you how it stores stuff in SQLite.  I got sick of dealing with its crummy UI and took some inspiration from Rails.

Rails Active Record implementation uses the database schema definition as the source of record and then derives the attributes in the classes (one per table) from that model.  The database is kept in sync with the application logic via *migrations*.

That was a great idea.  So I stole it.  The migrations part.  And using the database schema itself. Eventually.  But then dealing with SQLite when it is installed on an iPhone is a little bit of a hassle as far as bootstrapping the schema so I moved back to the code level...

The Objective C runtime has all the information required in it already (ARE YOU LISTENING CORE DATA PEOPLE?) to construct a meta model that can be translated into a SQLite schema for some subset of interesting types.  Its just all in these sort of inconvenient C functions.  Which I Objectified just for the purposes of this.

## Example

Suppose you have your generic social networking kind of schema.  You have Users, Posts, Likes, Comments, Followers...you want to keep this stuff in your local database.  First thing you do is subclass DBModel for each database entity you have.

```objc
@interface User : DBModel

@property (nonatomic, strong) NSString* username;
@property (nonatomic, strong) NSString* profileUrl;
@property (nonatomic) NSInteger followerCount;

@end
```

## Database Connections

The database connection is owned by the DBModel class.  You just have to set the name of it and it will be opened when you use it.

```objc
// set the database file name
[DBModel setDatabaseName:@"mydatabase"];
// open the database and run the migrations
[DBModel queue];
```

For thread safety, we use FMDBQueue to serialize database access.  If you are going to do a lot of database things in a row, you will want to use the queue explicitly.  However, if you are just doing a one liner it isn't really worth it and convenience methods exist.  So we could just do:

```objc
User* user = [User new];
user.username = @"rocket";
user.profileUrl = "http://server.com/images/rocket_profile.png";
user.followerCount = 5;
[user save];
```

On the other hand if you are going to mess with a whole lot of records at once you might as well do the queue version.

```objc
[[DBModel queue]inDatabase:^(FMDatabase* db) 
{ 
    [user saveInDatabase: db]; 
}];
```

DBModel includes an integer property called id which is the generated primary key in the database.  Since this is our first record it is a fair bet that the primary key is 1.  So you could get it back by primary key or doing a match on username.

```objc
// primary key fetch
User* user = [User find:@(1)];
User* user2 = [User find:@[@"username": @"rocket"]];

if(user == user2)
{
    NSLog(@"They are the same object!");
}
else
{
    NSLog(@"This doesn't happen because of the identity cache!");
}
```

Objects are stored in a weak cache by primary key.  If you fetch the same record, you get back the identical same object.  Nifty, no?

## Relationships

I punted on relationships.  Lets be real, phones are nothing but lists of lists of lists of lists.  I didn't think it was worthwhile to model relationships.  Foreign keys are not hard to deal with.  Just add a readonly method to get related objects.  Like so:

```objc
-(NSArray*)posts
{
    return [Post fetchAll:@[@"user_id": @(self.id)]];
}
```

The query dictionary works on equality - however if one of the values is an array, then an IN query is generated. This is adequate 80% of the time.  For that other 20% there's SQL.

```objc
+(NSArray*)findBySqlWhere:(NSString*)sql parameters:(NSArray*)params;

NSArray* topUsers = [User findBySqlWhere: @"followerCount > ? ORDER BY followerCount DESC LIMIT 50" parameters:@[@(100)]];
```

## Migrations

Check out DBModel+DBMigrations.h.  The main thing to understand is that a migration is a class named DBMigration_<number>.  A table is kept in the database with the number of the last migration run on it.  Upon opening the database, all of the migrations that need to be run are run in order.  This is accomplished by just trying to do NSClassFromString([NSString stringWithFormat: @"DBMigration_%d",migration]) until it returns nil.

A typical migration looks like:

```objc
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
```

Yes, Virginia, even the DatabaseMigrationLevel is just a DBModel.  So don't go using that class name, thanks.

No, I don't know how to do this bit in Swift.  You might have to fake it with some Class.createTableInDatabase(db) or somesuch.  The good news is all the create table statements use CREATE TABLE IF NOT EXISTS so calling them every time is (mostly) harmless.

## Installation 

You need FMDB and my SmalltalkCollections extension.  They are added as submodules.  So, after cloning this thing you need to execute a couple command line goodies:

```bash
git submodule init
git submodule update
```

Then you can add the xcode framework into your project, add SQLite library, and add this framework as a build pre-req in your app project.  This should all be something you already know how to do.

## JSON

So you've got a web service that is spitting JSON at you and you need to turn it into objects and then database records?  There are a couple handy class methods that do this for you assuming you named your properties the same as the JSON dictionaries.  

```objc
// mapping from json - transient
+(NSArray*)fromJsonArray:(NSArray*)items;
+(instancetype)fromJsonDictionary:(NSDictionary*)items;

// mapping from json - persistent
+(NSArray*)fromJsonArray:(NSArray*)items inDatabase:(FMDatabase*)db;
+(instancetype)fromJsonDictionary:(NSDictionary*)items inDatabase:(FMDatabase*)db;
```

The former doesn't save objects in the database unless they are already there - then it updates them.

The second pair stores everything it gets into the database.

```json
{"users": (
	{"username": "George"},
	{"username":"John"},
	{"username":"Paul"},
	{"username":"Ringo"}
)}
```
so you might just do:

```objc
[DBModel queue]inDatabase:^(FMDatabase*db)
{
	[User fromJsonArray:json[@"users"] inDatabase:db];
}];
```

and you've saved the Beatles into your database. Getting by with a little help from the runtime. You can go the other way - turn them into arrays of dictionaries using the property databaseColumnValues.  

## There's More!

Explore the DBModel class - it is insanely configuable.  For instance, you can change what constitutes a primary key by overriding primaryKeyPropertyNames.  There is a default ordering too which is newest first.  You can override that for a class by providing a new implementation of defaultOrderings. 

Here is the header for your enjoyment.

```objc
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
```

## Author

tblanchard, tblanchard@mac.com

## License

ObjectiveFMDB is available under the MIT license. See the LICENSE file for more info. Thanks to Gus Mueller for writing FMDB. It really made this easy to write.
