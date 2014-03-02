#!/usr/bin/env python
import checks
import json
import logging
import pika
import threading
import sched
import time

KEEPALIVE_PERIOD = 30
PERIOD = 30
START_PERIOD = 5

logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.INFO)

def connectMq():
  rabbitmq = json.loads(
      open('/etc/sensu/conf.d/rabbitmq.json', 'r').read())['rabbitmq']

  credentials = pika.PlainCredentials(rabbitmq['user'], rabbitmq['password'])

  connection = pika.BlockingConnection(
      pika.ConnectionParameters(rabbitmq['host'],
        virtual_host=rabbitmq['vhost'], credentials=credentials))

  return connection.channel()

def keepalive():
  scheduler.enter(KEEPALIVE_PERIOD, 1, pollMetrics, ())
  keepalive = {
      'name': 'metricmon',
      'timestamp': int(time.time())
      }
  logging.debug('Sending keepalive %s', keepalive)
  mq.basic_publish(exchange='', routing_key='keepalives', body=json.dumps(keepalive))

def pollMetrics():
  scheduler.enter(PERIOD, 1, pollMetrics, ())
  logging.debug('Polling metrics ..')

  results = checks.Checks().run()
  if not results:
    return

  for target, check, code, message in results:
    result = {
        'client': 'metricmon',
        'check': {
          'name': '%s|%s' % (target, check),
          'issued': int(time.time()),
          'output': message,
          'status': code,
          'standalone': True
          }
        }
    logging.info('Publishing result %s', result)
    mq.basic_publish(exchange='', routing_key='results',
        body=json.dumps(result))

if __name__ == '__main__':
  mq = connectMq()
  scheduler = sched.scheduler(time.time, time.sleep)
  scheduler.enter(START_PERIOD, 1, pollMetrics, ())

  # This will schedule keepalives to be sent every KEEPALIVE_PERIOD
  keepalive()

  scheduler.run()
  connection.close()