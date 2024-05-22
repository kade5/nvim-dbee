package adapters

import (
	"context"
	"database/sql"
	"fmt"
	nurl "net/url"

	"github.com/kndndrj/nvim-dbee/dbee/core"
	"github.com/kndndrj/nvim-dbee/dbee/core/builders"
)

var (
	_ core.Driver           = (*sqlServerDriver)(nil)
	_ core.DatabaseSwitcher = (*sqlServerDriver)(nil)
)

type sqlServerDriver struct {
	c   *builders.Client
	url *nurl.URL
}

func (c *sqlServerDriver) Query(ctx context.Context, query string) (core.ResultStream, error) {
	// run query, fallback to affected rows
	return c.c.QueryUntilNotEmpty(ctx, query, "select @@ROWCOUNT as 'Rows Affected'")
}

func (c *sqlServerDriver) Columns(opts *core.TableOptions) ([]*core.Column, error) {
	return c.c.ColumnsFromQuery(`
		SELECT
			column_name,
			data_type
		FROM information_schema.columns
			WHERE table_name='%s' AND
			table_schema = '%s'`,
		opts.Table,
		opts.Schema,
	)
}

func (c *sqlServerDriver) Structure() ([]*core.Structure, error) {
	query := `SELECT table_schema, table_name FROM INFORMATION_SCHEMA.TABLES
		UNION ALL
		SELECT SPECIFIC_SCHEMA, SPECIFIC_NAME from INFORMATION_SCHEMA.ROUTINES
		where ROUTINE_TYPE in ('PROCEDURE', 'FUNCTION')
	`

	rows, err := c.Query(context.TODO(), query)
	if err != nil {
		return nil, err
	}

	children := make(map[string][]*core.Structure)

	for rows.HasNext() {
		row, err := rows.Next()
		if err != nil {
			return nil, err
		}

		// We know for a fact there are 2 string fields (see query above)
		schema := row[0].(string)
		table := row[1].(string)

		children[schema] = append(children[schema], &core.Structure{
			Name:   table,
			Schema: schema,
			Type:   core.StructureTypeTable,
		})

	}

	var layout []*core.Structure

	for k, v := range children {
		layout = append(layout, &core.Structure{
			Name:     k,
			Schema:   k,
			Type:     core.StructureTypeNone,
			Children: v,
		})
	}

	return layout, nil
}

func (c *sqlServerDriver) Close() {
	c.c.Close()
}

func (c *sqlServerDriver) ListDatabases() (current string, available []string, err error) {
	query := `
		SELECT DB_NAME(), name
		FROM sys.databases
		WHERE name != DB_NAME();
	`

	rows, err := c.Query(context.TODO(), query)
	if err != nil {
		return "", nil, err
	}

	for rows.HasNext() {
		row, err := rows.Next()
		if err != nil {
			return "", nil, err
		}

		// We know for a fact there are 2 string fields (see query above)
		current = row[0].(string)
		available = append(available, row[1].(string))
	}

	return current, available, nil
}

func (c *sqlServerDriver) SelectDatabase(name string) error {
	q := c.url.Query()
	q.Set("database", name)
	c.url.RawQuery = q.Encode()

	db, err := sql.Open("sqlserver", c.url.String())
	if err != nil {
		return fmt.Errorf("unable to switch databases: %w", err)
	}

	c.c.Swap(db)

	return nil
}
