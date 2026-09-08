package main

import (
	"context"
	"fmt"
	"reflect"
	"sort"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// These expectations describe the separately implemented collection extension's
// public interface. No Racket compiler metadata is used to derive expectations.
func checkCollections(ctx context.Context, session *mcp.ClientSession) {
	tools, err := session.ListTools(ctx, nil)
	if err != nil {
		panic(err)
	}
	names := []string{}
	for _, tool := range tools.Tools {
		names = append(names, tool.Name)
	}
	sort.Strings(names)
	if !reflect.DeepEqual(names, []string{"search-articles", "search-books"}) {
		panic(fmt.Sprintf("extension tool names: %v", names))
	}
	templates, err := session.ListResourceTemplates(ctx, nil)
	if err != nil {
		panic(err)
	}
	uris := map[string]string{}
	for _, template := range templates.ResourceTemplates {
		uris[template.Name] = template.URITemplate
	}
	if len(templates.ResourceTemplates) != 2 || !reflect.DeepEqual(uris, map[string]string{
		"books": "book:///{id}", "articles": "article:///{id}",
	}) {
		panic(fmt.Sprintf("extension resource templates: %v", uris))
	}
	for _, tc := range []struct{ uri, text string }{
		{"book:///a%20b", "First book"}, {"article:///a%20b", "First article"},
	} {
		result, err := session.ReadResource(ctx, &mcp.ReadResourceParams{URI: tc.uri})
		if err != nil {
			panic(err)
		}
		if len(result.Contents) != 1 || result.Contents[0].URI != tc.uri || result.Contents[0].Text != tc.text {
			panic(fmt.Sprintf("extension resource read: %+v", result))
		}
	}
	for _, tc := range []struct {
		name, query string
		want        []string
	}{
		{"search-books", "book", []string{"a b", "two"}},
		{"search-articles", "article", []string{"a b", "essay"}},
		{"search-articles", "book", []string{}},
	} {
		result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: tc.name, Arguments: map[string]any{"query": tc.query}})
		if err != nil {
			panic(err)
		}
		items, ok := result.StructuredContent.([]any)
		if result.IsError || !ok {
			panic(fmt.Sprintf("extension search result: %+v", result))
		}
		got := []string{}
		for _, item := range items {
			id, ok := item.(string)
			if !ok {
				panic("extension search returned a non-string ID")
			}
			got = append(got, id)
		}
		sort.Strings(got)
		if !reflect.DeepEqual(got, tc.want) {
			panic(fmt.Sprintf("extension search %s: %v", tc.name, got))
		}
	}
	for _, tc := range []struct{ uri, prefix, value string }{
		{"book:///{id}", "t", "two"}, {"article:///{id}", "e", "essay"},
	} {
		result, err := session.Complete(ctx, &mcp.CompleteParams{
			Ref:      &mcp.CompleteReference{Type: "ref/resource", URI: tc.uri},
			Argument: mcp.CompleteParamsArgument{Name: "id", Value: tc.prefix},
		})
		if err != nil {
			panic(err)
		}
		if !reflect.DeepEqual(result.Completion.Values, []string{tc.value}) {
			panic(fmt.Sprintf("extension completion: %+v", result))
		}
	}
	fmt.Println("Official Go SDK: separate collection extension, independent helper bindings, generated search tools, encoded resource reads, and template completion passed.")
}
