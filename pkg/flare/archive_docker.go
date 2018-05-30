// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2018 Datadog, Inc.

// +build docker

package flare

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"text/tabwriter"

	"github.com/docker/docker/api/types"

	"github.com/DataDog/datadog-agent/pkg/util/docker"
	"github.com/DataDog/datadog-agent/pkg/util/log"
)

func zipDockerSelfInspect(tempDir, hostname string) error {
	du, err := docker.GetDockerUtil()
	if err != nil {
		return err
	}

	co, err := du.InspectSelf()
	if err != nil {
		return err
	}

	// Serialise as JSON
	jsonStats, err := json.Marshal(co)
	if err != nil {
		return err
	}
	var out bytes.Buffer
	json.Indent(&out, jsonStats, "", "\t")
	serialized := out.Bytes()

	f := filepath.Join(tempDir, hostname, "docker_inspect.log")
	w, err := NewRedactingWriter(f, os.ModePerm, true)
	if err != nil {
		return err
	}
	defer w.Close()

	w.RegisterReplacer(log.Replacer{
		Regex: regexp.MustCompile(`\"Image\": \"sha256:\w+"`),
		ReplFunc: func(s []byte) []byte {
			m := string(s[10 : len(s)-1])
			shaResolvedInspect, _ := du.ResolveImageName(m)
			return []byte(shaResolvedInspect)
		},
	})

	_, err = w.Write(serialized)
	return err
}

func zipDockerPs(tempDir, hostname string) error {
	du, err := docker.GetDockerUtil()
	if err != nil {
		return err
	}
	options := types.ContainerListOptions{All: true}
	containerList, err := du.RawContainerList(options)
	if err != nil {
		return err
	}

	// Opening out file
	f := filepath.Join(tempDir, hostname, "docker_ps.log")
	file, err := os.Create(f)
	if err != nil {
		return err
	}
	defer file.Close()

	w := tabwriter.NewWriter(file, 20, 0, 3, ' ', 0)

	fmt.Fprintln(w, "CONTAINER ID\tIMAGE\tCOMMAND\tSTATUS\tPORTS\tNAMES\t")
	// Removed CREATED as it only shows a timestamp in the API
	for _, c := range containerList {
		fmt.Fprintf(w, "%s\t%s\t%q\t%s\t%v\t%v\t\n",
			c.ID[:12], c.Image, c.Command, c.Status, c.Ports, c.Names)
		w.Flush()
	}

	return err
}
