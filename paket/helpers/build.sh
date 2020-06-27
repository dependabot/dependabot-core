#!/usr/bin/env bash
# -*- coding: utf-8 -*-

dotnet tool restore
dotnet build -c Release
